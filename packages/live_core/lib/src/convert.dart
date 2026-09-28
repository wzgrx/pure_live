/// [value] when it is a [T], else null (reading loosely typed JSON).
T? asT<T>(Object? value) => value is T ? value : null;
