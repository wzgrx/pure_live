class ReleaseModel {
  final String version;
  final String title;
  final String date;
  final String github;
  final AuthorModel author;
  final String changelog;
  final List<ReleaseFileModel> files;

  ReleaseModel({
    required this.version,
    required this.title,
    required this.date,
    required this.github,
    required this.author,
    required this.changelog,
    required this.files,
  });

  factory ReleaseModel.fromJson(Map<String, dynamic> json) {
    final rawAuthor = json['author'];
    final rawFiles = json['files'];
    return ReleaseModel(
      version: _releaseString(json['version']),
      title: _releaseString(json['title']),
      date: _releaseString(json['date']),
      github: _releaseString(json['github']),
      author: AuthorModel.fromJson(rawAuthor is Map ? Map<String, dynamic>.from(rawAuthor) : const {}),
      changelog: _releaseString(json['changelog']),
      files: rawFiles is List
          ? rawFiles
                .whereType<Map>()
                .map((item) => ReleaseFileModel.fromJson(Map<String, dynamic>.from(item)))
                .toList(growable: false)
          : const [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'title': title,
      'date': date,
      'github': github,
      'author': author.toJson(),
      'changelog': changelog,
      'files': files.map((e) => e.toJson()).toList(),
    };
  }
}

class AuthorModel {
  final String name;
  final String avatar;
  final String profile;

  AuthorModel({required this.name, required this.avatar, required this.profile});

  factory AuthorModel.fromJson(Map<String, dynamic> json) {
    return AuthorModel(
      name: _releaseString(json['name']),
      avatar: _releaseString(json['avatar']),
      profile: _releaseString(json['profile']),
    );
  }

  Map<String, dynamic> toJson() {
    return {'name': name, 'avatar': avatar, 'profile': profile};
  }
}

class ReleaseFileModel {
  final String name;
  final String size;
  final int downloads;
  final String url;

  ReleaseFileModel({required this.name, required this.size, required this.downloads, required this.url});

  factory ReleaseFileModel.fromJson(Map<String, dynamic> json) {
    return ReleaseFileModel(
      name: _releaseString(json['name']),
      size: _releaseString(json['size']),
      downloads: _releaseInt(json['downloads']),
      url: _releaseString(json['url']),
    );
  }

  Map<String, dynamic> toJson() {
    return {'name': name, 'size': size, 'downloads': downloads, 'url': url};
  }
}

String _releaseString(Object? value) {
  if (value == null) return '';
  return value is String ? value : value.toString();
}

int _releaseInt(Object? value) {
  final parsed = switch (value) {
    int number => number,
    num number => number.toInt(),
    String text => int.tryParse(text.trim()) ?? 0,
    _ => 0,
  };
  return parsed < 0 ? 0 : parsed;
}
