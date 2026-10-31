// ===== features/{{feature}}/presentation/cubit/{{feature}}_cubit.dart =====
sealed class {{Feature}}State extends Equatable {
  const {{Feature}}State();
  @override
  List<Object?> get props => const [];
}
final class {{Feature}}Loading extends {{Feature}}State { const {{Feature}}Loading(); }
final class {{Feature}}Loaded extends {{Feature}}State {
  const {{Feature}}Loaded(this.items);
  final List<{{Entity}}> items;
  @override
  List<Object?> get props => [items];
}
final class {{Feature}}Failed extends {{Feature}}State {
  const {{Feature}}Failed(this.failure);
  final AppFailure failure;
  @override
  List<Object?> get props => [failure];
}

class {{Feature}}Cubit extends Cubit<{{Feature}}State> {
  {{Feature}}Cubit(this._get{{Entity}}s) : super(const {{Feature}}Loading());
  final Get{{Entity}}s _get{{Entity}}s;

  Future<void> load() async {
    emit(const {{Feature}}Loading());
    final result = await _get{{Entity}}s();
    if (isClosed) return;
    emit(switch (result) {
      Success(:final value) => {{Feature}}Loaded(value),
      Failure(:final failure) => {{Feature}}Failed(failure),
    });
  }
}

// ===== features/{{feature}}/presentation/ui/{{feature}}_page.dart =====
@RoutePage()
class {{Feature}}Page extends StatelessWidget implements AutoRouteWrapper {
  const {{Feature}}Page({super.key});

  @override
  Widget wrappedRoute(BuildContext context) => BlocProvider(
        create: (context) => {{Feature}}Cubit(context.read())..load(),
        child: this,
      );

  @override
  Widget build(BuildContext context) => AppScaffold(
        title: context.l10n.{{feature}}_title,
        body: BlocBuilder<{{Feature}}Cubit, {{Feature}}State>(
          builder: (context, state) => switch (state) {
            {{Feature}}Loading() => const Center(child: AppSpinner()),
            {{Feature}}Failed(:final failure) => AppErrorView(
                message: failure.localized(context),
                onRetry: context.read<{{Feature}}Cubit>().load,
              ),
            {{Feature}}Loaded(:final items) when items.isEmpty =>
              AppEmptyView(message: context.l10n.{{feature}}_empty),
            {{Feature}}Loaded(:final items) => ListView(
                children: [for (final item in items) Text(item.id)],
              ),
          },
        ),
      );
}
