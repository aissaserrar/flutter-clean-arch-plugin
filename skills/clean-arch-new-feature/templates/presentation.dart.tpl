// ===== features/{{feature}}/presentation/cubit/{{feature}}_cubit.dart =====
// Full feature: the cubit takes use cases. Feature with a repository: take {{Feature}}Repository.
// Thin feature: take the typed API client from core/http instead. All classes of the cubit stay in
// this one file: cubit, (events), state, (presentation events).
class {{Feature}}Cubit extends Cubit<{{Feature}}State> {
  {{Feature}}Cubit(this._get{{Entity}}s) : super(const {{Feature}}StateLoading());
  final Get{{Entity}}s _get{{Entity}}s;

  Future<void> load() async {
    emit(const {{Feature}}StateLoading());
    final result = await _get{{Entity}}s();
    if (isClosed) return;
    emit(switch (result) {
      Success(:final value) => {{Feature}}StateSuccess(value),
      Failure(:final failure) => {{Feature}}StateFailure(failure),
    });
  }
}

sealed class {{Feature}}State extends Equatable {
  const {{Feature}}State();
  @override
  List<Object?> get props => const [];
}
final class {{Feature}}StateLoading extends {{Feature}}State { const {{Feature}}StateLoading(); }
final class {{Feature}}StateSuccess extends {{Feature}}State {
  const {{Feature}}StateSuccess(this.items);
  final List<{{Entity}}> items;
  @override
  List<Object?> get props => [items];
}
final class {{Feature}}StateFailure extends {{Feature}}State {
  const {{Feature}}StateFailure(this.failure);
  final AppFailure failure;
  @override
  List<Object?> get props => [failure];
}

// ===== features/{{feature}}/presentation/ui/{{feature}}_page.dart =====
// Public page provides the cubit; private content underneath renders it.
// auto_route: add @RoutePage() and `implements AutoRouteWrapper` (provide the cubit in wrappedRoute).
class {{Feature}}Page extends StatelessWidget {
  const {{Feature}}Page({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (context) => {{Feature}}Cubit(context.read())..load(),
        child: const _{{Feature}}Content(),
      );
}

class _{{Feature}}Content extends StatelessWidget {
  const _{{Feature}}Content();

  @override
  Widget build(BuildContext context) => AppScaffold(
        title: context.l10n.{{feature}}_title,
        body: BlocBuilder<{{Feature}}Cubit, {{Feature}}State>(
          builder: (context, state) => switch (state) {
            {{Feature}}StateLoading() => const Center(child: AppSpinner()),
            {{Feature}}StateFailure(:final failure) => AppErrorView(
                message: failure.localized(context),
                onRetry: context.read<{{Feature}}Cubit>().load,
              ),
            {{Feature}}StateSuccess(:final items) when items.isEmpty =>
              AppEmptyView(message: context.l10n.{{feature}}_empty),
            {{Feature}}StateSuccess(:final items) => ListView(
                children: [for (final item in items) Text(item.id)],
              ),
          },
        ),
      );
}
