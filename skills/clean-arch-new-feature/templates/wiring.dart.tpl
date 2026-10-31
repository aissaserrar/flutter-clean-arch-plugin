// ===== features/{{feature}}/{{feature}}_routes.dart =====
abstract final class {{Feature}}Routes {
  static List<AutoRoute> get routes => [
        AutoRoute(page: {{Feature}}Route.page, path: '/{{feature}}'),
      ];
}

// ===== features/{{feature}}/{{feature}}_providers.dart =====
final {{feature}}Providers = <SingleChildWidget>[
  Provider<Remote{{Feature}}DataSource>(
    create: (context) => Remote{{Feature}}DataSource(context.read()),
  ),
  Provider<{{Feature}}Repository>(
    create: (context) => AppConfig.useMocks
        ? Mock{{Feature}}Repository()
        : {{Feature}}RepositoryImpl(context.read<Remote{{Feature}}DataSource>()),
  ),
  Provider(create: (context) => Get{{Entity}}s(context.read())),
];

// ===== add to bootstrap/global_providers.dart =====
//   ...{{feature}}Providers,
// ===== add to router/app_router.dart routes =====
//   ...{{Feature}}Routes.routes,
// ===== add to l10n/app_en.arb =====
//   "{{feature}}_title": "{{Feature}}",
//   "{{feature}}_empty": "Nothing here yet"
