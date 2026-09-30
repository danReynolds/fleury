import 'package:shelf/shelf.dart';

/// One explicit docs origin, with no browser credentials or wildcard access.
class DocsOrigin {
  DocsOrigin(this.origin) {
    if (origin == null) return;
    final uri = Uri.parse(origin!);
    if (uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.path.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw StateError('FLEURY_PAD_DOCS_ORIGIN must be an HTTPS origin.');
    }
  }

  final String? origin;
  bool allows(String? candidate) => origin != null && candidate == origin;

  Map<String, String> headers(Request request) =>
      allows(request.headers['origin'])
      ? {
          'access-control-allow-origin': origin!,
          'vary': 'Origin',
          'access-control-expose-headers': 'x-compile-ms',
        }
      : {};

  Response preflight(Request request) {
    final method = request.headers['access-control-request-method'];
    final headers =
        request.headers['access-control-request-headers']
            ?.toLowerCase()
            .split(',')
            .map((header) => header.trim()) ??
        [];
    if (!allows(request.headers['origin']) ||
        (method != 'POST' && method != 'GET') ||
        headers.any(
          (header) => !{'content-type', 'x-fleury-build'}.contains(header),
        )) {
      return Response.forbidden('Unrecognized docs request.');
    }
    return Response(
      204,
      headers: {
        ...this.headers(request),
        'access-control-allow-methods': 'GET, POST',
        'access-control-allow-headers': 'Content-Type, X-Fleury-Build',
        'access-control-max-age': '600',
      },
    );
  }
}
