#!/usr/bin/env bash
# Shared detection helpers. Sourced by the scanners, not run on its own. Run from the project root (needs lib/).
#
# Why this exists: real projects rarely extend Cubit or GetxController directly. They have their own base
# classes (BaseCubit<T>, DataCubit<T>, PaginatedCubit<T>, GetxFormController, ...), so matching only the
# framework class names undercounts badly. resolve_bases follows `class X extends <known base>` (also when the
# header spans several lines) and returns an ERE alternation of the seed names plus every class that extends them.
#
#   resolve_bases 'Cubit|Bloc'  ->  Bloc|BaseCubit|Cubit|DataCubit|PaginatedCubit
#   detect_bases                ->  sets CUBIT_BASES, GETX_BASES, RE_CUBIT, RE_GETX
#
# RE_CUBIT / RE_GETX match a class header line: "extends <base>" followed by generics, a space, "{" or the end.
# class_pairs: one line per class declaration with a parent:  Name<TAB>Parent
# Reads multi-line headers (up to 5 lines) and strips nested generics, so
#   abstract class PaginatedCubit<T extends PaginatedResponse>
#       extends BaseCubit<PaginatedState<T>> {
# gives  PaginatedCubit<TAB>BaseCubit.
class_pairs() {
  grep -rlE --include='*.dart' 'class +[A-Za-z0-9_]+' lib 2>/dev/null | xargs awk '
    FNR == 1 { pend = ""; n = 0 }
    { line = $0
      if (pend == "") {
        if (line ~ /^[ \t]*(\/\/|\*)/) next
        if (line ~ /(^|[ \t])class +[A-Za-z0-9_]+/) { pend = line; n = 1 } else next
      } else { pend = pend " " line; n++ }
      if (pend ~ /\{/ || n >= 5) {
        h = pend; pend = ""
        while (gsub(/<[^<>]*>/, "", h)) ;
        if (match(h, /class +[A-Za-z0-9_]+ +extends +[A-Za-z0-9_]+/)) { t = substr(h, RSTART, RLENGTH); split(t, w, " "); print w[2] "\t" w[4] }
      } }' 2>/dev/null
}

# resolve_bases <seed ERE alternation> [pairs]: seeds plus every class that extends them, transitively.
resolve_bases() {
  local pairs="${2:-}"
  [ -n "$pairs" ] || pairs="$(class_pairs)"
  printf '%s\n' "$pairs" | awk -F'\t' -v seeds="$1" '
    { cls[NR] = $1; par[NR] = $2 }
    END { alt = seeds
      for (pass = 0; pass < 8; pass++) { changed = 0
        for (i = 1; i <= NR; i++) if (!(cls[i] in known) && par[i] ~ ("^(" alt ")$")) { known[cls[i]] = 1; alt = alt "|" cls[i]; changed = 1 }
        if (!changed) break }
      printf "%s", alt }'
}

detect_bases() {
  # Already known (exported by a parent script such as audit.sh)? Then reuse it instead of scanning again.
  if [ -z "${CUBIT_BASES:-}" ] || [ -z "${GETX_BASES:-}" ]; then
    local pairs; pairs="$(class_pairs)"
    CUBIT_BASES="$(resolve_bases 'Cubit|Bloc|HydratedCubit|HydratedBloc|ReplayCubit|ReplayBloc|BlocBase' "$pairs")"
    GETX_BASES="$(resolve_bases "$GX_CONTROLLER_BASES" "$pairs")"
  fi
  RE_CUBIT="extends +($CUBIT_BASES)( *<|[ {]|\$)"
  RE_GETX="extends +($GETX_BASES)( *<|[ {]|\$)"
}

# ---- Feature units: which "feature" does a file belong to? ----
# UNIT_AWK defines unit_of(path) for awk programs:   awk "$UNIT_AWK"' { print unit_of($0) }'
#   lib/features/<f>/...                 -> <f>
#   .../(screens|pages|views|modules)/X  -> X without _screen/_tab/_page...; generic containers (tabs, common, ...) are skipped
#   anything else (controllers/, services/, core/...) -> the file name without its suffix (cart_controller.dart -> cart)
# so lib/screens/tabs/home_tab/home_tab_controller.dart and lib/screens/home_screen/home_controller.dart both give "home".
UNIT_AWK='
function unit_norm(st) { while (st ~ /_(screen|screens|page|pages|view|views|tab|tabs|widget|widgets|controller|binding|bindings|bloc|cubit|state|model|service|provider|repository)$/) sub(/_[a-z]+$/, "", st); return st }
function unit_of(path,   a, base, rest, m, seg, i) {
  if (path ~ /^lib\/features\//) { split(path, a, "/"); return a[3] }
  base = path; sub(/.*\//, "", base); sub(/\.dart$/, "", base)
  if (match(path, /\/(modules|pages|screens|views)\//)) {
    rest = substr(path, RSTART + RLENGTH); m = split(rest, seg, "/")
    for (i = 1; i < m; i++) if (seg[i] !~ /^(tabs|tab|common|shared|components|widgets|base|utils|helpers|mixins|screens|pages|views|modules|core)$/) return unit_norm(seg[i])
  }
  return unit_norm(base)
}
'

# ---- GetX usage of any kind on a line (used for per-file / per-unit totals) ----
RE_GETX_USAGE="import +['\"]package:get/|(^|[^A-Za-z0-9_])(Obx|ObxValue|GetBuilder|GetMaterialApp|GetCupertinoApp)(<[^>]*>)?[(]|\\.obs([^A-Za-z0-9_]|\$)|(^|[^A-Za-z0-9_])Get\\.[a-zA-Z]+|extends +(GetView|GetWidget|GetResponsiveView)<"

# ---- unit_files <unit>: the non-generated lib files that belong to a unit (see UNIT_AWK) ----
unit_files() {
  find lib -name '*.dart' ! -name '*.g.dart' ! -name '*.freezed.dart' ! -name '*.gr.dart' ! -name '*.config.dart' ! -name 'app_localizations*.dart' 2>/dev/null | sort \
    | awk -v want="$1" "$UNIT_AWK"' { if (unit_of($0) == want) print $0 }'
}

# ---- resolve_target <name>: files of the feature unit with exactly that name (run from the project root) ----
# Prints one path per line. Exit 1 and no output when the name is not a unit (callers then treat it as a path).
resolve_target() {
  local out; out="$(unit_files "$1")"
  [ -n "$out" ] || return 1
  printf '%s\n' "$out"
}

# =====================================================================================================
# GetX API catalog: ONE place that says what "uses GetX" means. Every scanner builds on these variables.
# Source: https://pub.dev/documentation/get/latest/get/get-library.html (classes, mixins, extensions, top-level
# members) and https://pub.dev/packages/get, checked 2026-11-02. When a new GetX version adds API, add it here
# and nowhere else; scripts/check_getx_coverage.sh proves every scanner still sees every entry.
# Names that other libraries also use (Response, FormData, MultipartFile, Transition, Value, Node, Worker, Routing)
# are NOT counted on their own: they only matter inside files that import package:get/.
# =====================================================================================================
GX_NB='(^|[^A-Za-z0-9_])'
GX_END='([^A-Za-z0-9_]|$)'

# Members of the Get object (GetNavigation, Inst and the extensions on Get), by area
GX_NAV_MEMBERS='toNamed|to|offAllNamed|offAll|offNamedUntil|offNamed|offUntil|offAndToNamed|off|until|back|removeRoute|removeRouteBefore|arguments|parameters|currentRoute|previousRoute|rawRoute|routing|rootDelegate|nestedKey|global|keys|key|isSnackbarOpen|isDialogOpen|isBottomSheetOpen|closeAllSnackbars|closeCurrentSnackbar|closeOverlay|closeAllDialogsAndBottomSheets|toEnd|appUpdate|forceAppUpdate|reloadRoute|isOpaqueRouteDefault|isPopGestureEnable|defaultTransition|defaultDurationTransition|defaultPopGesture|defaultGlobalState|routerDelegate|routeInformationParser|addPages|addPage|clearRouteTree|searchDelegate'
GX_DI_MEMBERS='lazyPut|lazyReplace|putAsync|put|find|create|deleteAll|delete|resetInstance|reset|isRegistered|isPrepared|replace|testMode|smartManagement|initialBinding'
GX_UI_MEMBERS='defaultDialog|dialog|bottomSheet|rawSnackbar|showSnackbar|snackbar|contextOverlay|overlayContext|context|width|height|theme|textTheme|isDarkMode|isPlatformDarkMode|changeThemeMode|changeTheme|deviceLocale|updateLocale|fallbackLocale|locale|focusScope|mediaQuery|size|statusBarHeight|bottomBarHeight|iconColor|log|config|enableLog|engine|parent|snackBarStatus'

# Classes, mixins and enums (unambiguous names)
GX_STATE_WIDGETS='Obx|ObxValue|ObxWidget|GetX|GetBuilder|GetView|GetWidget|GetResponsiveView|GetResponsiveWidget|MixinBuilder|SimpleBuilder|ValueBuilder|GetRouterOutlet'
GX_CONTROLLER_BASES='Getx[A-Za-z0-9_]*|SuperController|GetLifeCycle|FullLifeCycleController|DisposableInterface|RxController|GetNotifier|GetMaterialController|GetxServiceMixin'
GX_MIXINS='StateMixin|FullLifeCycleMixin|GetLifeCycleBase|GetResponsiveMixin|GetSingleTickerProviderStateMixin|GetTickerProviderStateMixin|ScrollMixin|SingleGetTickerProviderMixin|GetStateUpdaterMixin|NotifyManager|RxObjectMixin|PageRouteReportMixin'
GX_RX='Rx|Rxn|RxBool|RxDouble|RxInt|RxList|RxMap|RxNum|RxSet|RxString|RxnBool|RxnDouble|RxnInt|RxnNum|RxnString|RxStatus|RxInterface|RxNotifier'
GX_ROUTING='GetMaterialApp|GetCupertinoApp|GetPage|GetPageRoute|GetMiddleware|GetObserver|GetNavigator|GetDelegate|GetInformationParser|GetNavConfig|GetModalBottomSheetRoute|CustomTransition|GetPageBuilder|PageRedirect|MiddlewareRunner'
GX_DI_CLASSES='Bindings|BindingsBuilder|GetInstance|GetInterface|SmartManagement|InstanceInfo'
GX_UI_CLASSES='GetBar|GetSnackBar|SnackbarController|SnackPosition|SnackStyle|SnackbarStatus|GetPlatform|GetUtils|ResponsiveScreen|ResponsiveScreenSettings'
GX_NET='GetConnect|GetConnectInterface|GetHttpClient|GetSocket|GraphQLResponse'
GX_STREAMS='GetStream|GetQueue|GetMicrotask|FastList|MiniStream|LightSubscription|GetStreamTransformation'
GX_WORKER_FUNCS='ever|everAll|once|debounce|interval'

# Extension members. Distinctive ones are counted in files that import package:get/; the broad list is only used
# to decide that an import must stay (kill_getx_finish.sh), never for counting.
GX_EXT_DISTINCT='trParams|trArgs|trPlural|tr|obx|capitalizeFirst|camelCase|paramCase|removeAllWhitespace|isNumericOnly|isAlphabetOnly|isNum|isEmail|isURL|isPhoneNumber|isNullOrBlank|isBlank|isLowerCase|isUpperCase|isDateTime|isBool|isVideo|isImage|isAudio|isTxt|isPDF|isHTML|isIPv4|isIPv6|isBinary|isHexadecimal|isVectorFileName|isCurrency|isUsername|isNotNull|isNull|printInfo|printError|toPrecision|paddingAll|paddingOnly|paddingSymmetric|paddingZero|marginAll|marginOnly|marginSymmetric|marginZero|sliverBox|addIf|addAllIf|assignAll|firstWhereOrNull'
GX_EXT_BROAD="$GX_EXT_DISTINCT|assign|nil|toggle|refresh|delay|capitalize|isEmptyOrNull|numericOnly|isCaseInsensitiveContains|isCaseInsensitiveContainsAny|lastWhereOrNull|obs"
GX_CONTEXT_EXT='width|height|theme|textTheme|mediaQuerySize|mediaQueryPadding|mediaQueryViewPadding|mediaQueryViewInsets|mediaQueryShortestSide|orientation|isLandscape|isPortrait|devicePixelRatio|textScaleFactor|showNavbar|isPhone|isSmallTablet|isLargeTablet|isTablet|responsiveValue|heightTransformer|widthTransformer|iconColor|isDarkMode'

# ---- Ready-made ERE for grep -E (each is one area of GetX usage) ----
RE_GX_IMPORT="import +['\"]package:get/|export +['\"]package:get/"
RE_GX_NAV="${GX_NB}Get\\.($GX_NAV_MEMBERS)${GX_END}|${GX_NB}($GX_ROUTING)${GX_END}"
RE_GX_DI="${GX_NB}Get\\.($GX_DI_MEMBERS)${GX_END}|${GX_NB}($GX_DI_CLASSES)${GX_END}|extends +Binding${GX_END}"
RE_GX_UI="${GX_NB}Get\\.($GX_UI_MEMBERS)${GX_END}|${GX_NB}($GX_UI_CLASSES)${GX_END}"
RE_GX_NET="${GX_NB}($GX_NET)${GX_END}"
RE_GX_STREAMS="${GX_NB}($GX_STREAMS)${GX_END}"
RE_GX_WIDGETS="${GX_NB}($GX_STATE_WIDGETS)(<[^>]*>)?[(]|extends +($GX_STATE_WIDGETS)${GX_END}"
RE_GX_REACTIVE="\\.obs${GX_END}|${GX_NB}($GX_RX)(<|[(.])|${GX_NB}($GX_MIXINS)${GX_END}|\\.obx[(]"
RE_GX_WORKERS="(^|[^.A-Za-z0-9_])($GX_WORKER_FUNCS)[(]"
RE_GX_TRANSLATIONS="extends +Translations${GX_END}"
RE_GX_OTHER_GET="${GX_NB}Get\\.[A-Za-z_][A-Za-z0-9_]*"
# Everything that is unambiguously GetX on one line (used for per-file totals)
RE_GX_ANY="$RE_GX_IMPORT|$RE_GX_NAV|$RE_GX_DI|$RE_GX_UI|$RE_GX_NET|$RE_GX_STREAMS|$RE_GX_WIDGETS|$RE_GX_REACTIVE|$RE_GX_WORKERS|$RE_GX_TRANSLATIONS|$RE_GX_OTHER_GET|extends +($GX_CONTROLLER_BASES)${GX_END}"
# A cheap SUPERSET of everything above, for the single scan of the whole project (the precise per-area patterns are
# then applied to that small result). It is short on purpose: BSD grep (macOS) slows down badly on long alternations
# of class names, so this uses prefixes (Get<Upper>, Rx<Letter>, Obx) and a few distinctive names.
# scripts/check_getx_coverage.sh proves that every catalog entry still matches it.
RE_GX_PREFILTER="package:get/|Get[.A-Zx]|Rx[A-Za-z<(]|Obx|MixinBuilder|SimpleBuilder|ValueBuilder|StateMixin|FullLifeCycle|DisposableInterface|SuperController|ScrollMixin|Binding|SmartManagement|MiddlewareRunner|GraphQLResponse|Snack(Position|Style|bar)|ResponsiveScreen|CustomTransition|PageRedirect|InstanceInfo|MiniStream|FastList|LightSubscription|NotifyManager|PageRouteReport|\\.obs|\\.obx|(ever|everAll|once|debounce|interval)[(]|extends +Translations"

# Extension usage, only meaningful in files that import package:get/
# Names that other libraries also use: counted only inside files that import package:get/ (with a dot or a call after them)
GX_AMBIGUOUS='Transition|ScreenType|PopMode|PreventDuplicateHandlingMode|RowStyle|Workers|Worker'
RE_GX_EXT="\\.($GX_EXT_DISTINCT)${GX_END}|[0-9]\\.(seconds|milliseconds|microseconds|minutes|hours|days)${GX_END}|${GX_NB}context\\.($GX_CONTEXT_EXT)${GX_END}|${GX_NB}($GX_AMBIGUOUS)[.(<]"
RE_GX_EXT_BROAD="\\.($GX_EXT_BROAD)${GX_END}|[0-9]\\.(seconds|milliseconds|microseconds|minutes|hours|days|delay)${GX_END}|${GX_NB}context\\.($GX_CONTEXT_EXT)${GX_END}"

# gx_import_files: the non-generated lib files that import package:get/ (the scope for extension counting)
gx_import_files() { grep -rlE --include='*.dart' --exclude='*.g.dart' --exclude='*.freezed.dart' --exclude='*.gr.dart' "$RE_GX_IMPORT" lib 2>/dev/null; }
# gx_related_packages: pubspec dependencies that belong to the GetX family (get_it and getwidget are NOT GetX)
gx_related_packages() {
  [ -f pubspec.yaml ] || return 0
  grep -oE '^[[:space:]]+(get|get_storage|get_server|get_connect|get_cli|getx_[a-z0-9_]+|[a-z0-9_]+_getx|get_x[a-z0-9_]*):' pubspec.yaml | tr -d ' :' | paste -sd, -
}
