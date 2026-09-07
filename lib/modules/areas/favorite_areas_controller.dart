import 'package:pure_live/common/index.dart';

class FavoriteAreasController extends GetxController with GetTickerProviderStateMixin {
  late TabController tabSiteController;

  var tabSiteIndex = 0.obs;
  // Read the persisted observable inside the page's Obx instead of retaining
  // the list object that happened to exist when this route was opened.
  List<LiveArea> get favoriteAreas => SettingsService.to.fav.favoriteAreas.v;
  @override
  void onInit() {
    tabSiteController = TabController(
      length: Sites().availableSites().length + 1,
      vsync: this,
      animationDuration: pureLiveTabTransitionDuration,
    );
    tabSiteController.addListener(() {
      tabSiteIndex.value = tabSiteController.index;
    });
    super.onInit();
  }

  @override
  void onClose() {
    tabSiteController.dispose();
    super.onClose();
  }
}
