import 'dart:async';

import 'package:pure_live/common/index.dart';
import 'package:pure_live/core/common/log.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pure_live/modules/auth/auth_controller.dart';
import 'package:pure_live/modules/auth/models/user_item.dart';
import 'package:pure_live/modules/auth/utils/firebase_manager.dart';

class UserServerRemoteController extends ServerRemotePageController<UserItem> {
  final rxSearchKeyword = "".obs;
  String searchKeyword = "";
  late bool isSuperAdmin;
  DocumentSnapshot? lastDocument;

  final adminCount = 0.obs;
  final managerCount = 0.obs;
  final userCount = 0.obs;
  Worker? _searchWorker;
  Timer? _searchTimer;
  int _searchVersion = 0;

  // Cloud I/O stays separate from cursor ownership and visible state. Tests
  // can control these boundaries without replacing pagination or filtering.
  String get currentUserUid => Get.find<AuthController>().user!.uid;

  Future<List<String>> readCloudUserIds() async {
    final snapshot = await FirebaseFirestore.instance.collection('users').get();
    return snapshot.docs.map((doc) => doc.id).toList();
  }

  Future<Map<String, String>> readCloudRoles(List<String>? uids) async {
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance.collection('permissions');
    if (uids != null) query = query.where(FieldPath.documentId, whereIn: uids);
    final snapshot = await query.get();
    return {for (final doc in snapshot.docs) doc.id: doc.data()['role'] ?? 'user'};
  }

  Future<void> writeCloudUser(String docId, Map<String, dynamic> updateData) =>
      FirebaseFirestore.instance.collection('users').doc(docId).update(updateData);

  @override
  void onInit() {
    super.onInit();
    isSuperAdmin = FirebaseManager.getInstance().isAdmin();
    _fetchGlobalStats();
    _searchWorker = ever(rxSearchKeyword, (String keyword) {
      if (isClosed) return;
      final version = ++_searchVersion;
      _searchTimer?.cancel();
      _searchTimer = Timer(const Duration(milliseconds: 500), () => unawaited(_commitSearch(keyword, version)));
    });
  }

  Future<void> _commitSearch(String keyword, int version) async {
    while (!isClosed && version == _searchVersion) {
      final active = activePageOperation;
      if (active == null) break;
      await active;
    }
    if (isClosed || version != _searchVersion || keyword == searchKeyword) return;
    // Preserve the old request's query and cursor until its transaction ends.
    // Only the latest still-current search intent can reset the directory.
    searchKeyword = keyword;
    lastDocument = null;
    await refreshData();
  }

  @override
  void onClose() {
    _searchVersion++;
    _searchTimer?.cancel();
    _searchWorker?.dispose();
    super.onClose();
  }

  Future<void> _fetchGlobalStats() async {
    if (isClosed) return;
    try {
      final userIds = await readCloudUserIds();
      if (isClosed) return;
      final permissionRoleMap = await readCloudRoles(null);
      if (isClosed) return;

      int admins = 0;
      int managers = 0;
      int users = 0;

      for (var uid in userIds) {
        String role = permissionRoleMap[uid] ?? 'user';
        int weight = FirebaseManager.roleWeights[role] ?? 2;
        if (weight == 0) admins++;
        if (weight == 1) managers++;
        if (weight == 2) users++;
      }

      adminCount.value = admins;
      managerCount.value = managers;
      userCount.value = users;
    } catch (e) {
      if (isClosed) return;
      Log.d("获取全局统计失败: $e");
    }
  }

  Future<List<DocumentSnapshot>> readCloudUsers({
    required int limitCount,
    required String keyword,
    required DocumentSnapshot? after,
  }) async {
    Query baseQuery = FirebaseFirestore.instance.collection('users');

    if (keyword.isNotEmpty) {
      String start = keyword.toLowerCase();
      String end = start.substring(0, start.length - 1) + String.fromCharCode(start.codeUnitAt(start.length - 1) + 1);
      baseQuery = baseQuery.where('email', isGreaterThanOrEqualTo: start).where('email', isLessThan: end);
    }

    baseQuery = baseQuery.orderBy('email').limit(limitCount);
    if (after != null) {
      baseQuery = baseQuery.startAfterDocument(after);
    }

    final userSnapshot = await baseQuery.get();
    return userSnapshot.docs;
  }

  @override
  Future<List<UserItem>> fetchNetworkData(int page, int pageSize) async {
    if (isClosed) return [];
    final currentUserUid = this.currentUserUid;
    final keyword = searchKeyword;
    var cursor = page == 1 ? null : lastDocument;

    List<UserItem> finalCleanList = [];
    List<DocumentSnapshot> allFetchedDocs = [];
    bool isCloudDrained = false;

    while (finalCleanList.length < pageSize && !isCloudDrained) {
      final int neededCount = pageSize - finalCleanList.length;
      final rawDocs = await readCloudUsers(limitCount: neededCount, keyword: keyword, after: cursor);
      if (isClosed) return [];

      if (rawDocs.isEmpty) {
        isCloudDrained = true;
        break;
      }

      cursor = rawDocs.last;
      allFetchedDocs.addAll(rawDocs);

      List<String> uidsInPage = rawDocs.map((doc) => doc.id).toList();
      final permissionRoleMap = await readCloudRoles(uidsInPage);
      if (isClosed) return [];

      for (var doc in rawDocs) {
        String uid = doc.id;
        if (uid == currentUserUid) continue;

        Map<String, dynamic>? data = doc.data() as Map<String, dynamic>?;
        String email = data?['email'] ?? '';
        bool canUpload = data?['canUpload'] != false;
        String role = permissionRoleMap[uid] ?? 'user';

        if (!FirebaseManager.getInstance().canVisible(role)) continue;

        finalCleanList.add(UserItem(uid: uid, email: email, canUpload: canUpload, role: role));
      }

      if (rawDocs.length < neededCount) {
        isCloudDrained = true;
      }
    }

    finalCleanList.sort((a, b) {
      int weightA = FirebaseManager.roleWeights[a.role] ?? 2;
      int weightB = FirebaseManager.roleWeights[b.role] ?? 2;
      int cmp = weightA.compareTo(weightB);
      if (cmp == 0) return a.email.compareTo(b.email);
      return cmp;
    });

    if (finalCleanList.length > pageSize) {
      finalCleanList = finalCleanList.sublist(0, pageSize);

      int validDocIndex = -1;
      final lastValidItemUid = finalCleanList.last.uid;
      for (int i = 0; i < allFetchedDocs.length; i++) {
        if (allFetchedDocs[i].id == lastValidItemUid) {
          validDocIndex = i;
          break;
        }
      }
      if (validDocIndex != -1) {
        cursor = allFetchedDocs[validDocIndex];
      }
    }

    // Commit only after every chunk and its permissions succeeded. A failed
    // permission read must retry from the previous committed cursor.
    if (isClosed) return [];
    lastDocument = cursor;
    Log.d("获取用户列表成功: ${finalCleanList.length}");
    return finalCleanList;
  }

  Future<void> refreshByKeyword(String keyword) async {
    if (isClosed || keyword == rxSearchKeyword.value) return;
    // Invalidate an already-debounced waiter immediately, even while the Rx
    // notification for this new input is still waiting to be delivered.
    _searchVersion++;
    _searchTimer?.cancel();
    rxSearchKeyword.value = keyword;
  }

  Future<void> onConfigSaved(String docId, Map<String, dynamic> updateData) async {
    if (isClosed) return;
    await writeCloudUser(docId, updateData);
    if (isClosed) return;
    await refreshData();
  }
}
