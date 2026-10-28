#!/usr/bin/env python3
"""Предкомпиляционная проверка: типы, импорты, вызовы методов.
Не заменяет `flutter analyze`, но ловит частые ошибки без SDK."""
import re, pathlib, collections, sys

LIB = pathlib.Path('lib')
PKG = pathlib.Path('packages/mail_engine/lib')
files = sorted(list(LIB.rglob('*.dart')) + list(PKG.rglob('*.dart')))
src = {f: f.read_text(encoding='utf-8', errors='ignore') for f in files}

# 1) где определён каждый класс/enum/mixin/extension
defined = {}   # имя -> файл
for f, t in src.items():
    for m in re.finditer(r'^(?:abstract\s+|sealed\s+|final\s+|base\s+)*(?:class|enum|mixin|extension)\s+(\w+)', t, re.M):
        defined.setdefault(m.group(1), f)
    for m in re.finditer(r'^typedef\s+(\w+)', t, re.M):
        defined.setdefault(m.group(1), f)

# известные из Flutter/Dart SDK и популярных пакетов — не проверяем
SDK = set('''
Widget StatelessWidget StatefulWidget State BuildContext Key GlobalKey ValueKey UniqueKey
Text Icon Icons Color Colors Column Row Container Padding EdgeInsets SizedBox Expanded Flexible
Scaffold AppBar ListView ListTile GridView Card Divider Center Align Stack Positioned Wrap
TextStyle TextAlign TextOverflow FontWeight ThemeData Theme MaterialApp Navigator Route
MaterialPageRoute PageRouteBuilder showDialog showModalBottomSheet AlertDialog SimpleDialog
TextButton ElevatedButton FilledButton OutlinedButton IconButton FloatingActionButton
TextField TextFormField TextEditingController InputDecoration Form FormState
Future Stream StreamSubscription Timer Duration DateTime String int double bool List Map Set
Iterable Object Exception Error StackTrace Uri File Directory Platform Process
CircularProgressIndicator LinearProgressIndicator RefreshIndicator ScrollController
SingleChildScrollView CustomScrollView SliverList SliverAppBar NestedScrollView
Image AssetImage NetworkImage CircleAvatar Chip InkWell GestureDetector Dismissible
SnackBar ScaffoldMessenger BottomNavigationBar NavigationBar NavigationRail NavigationDestination
PopupMenuButton PopupMenuItem DropdownButton DropdownButtonFormField DropdownMenuItem
Switch SwitchListTile Checkbox CheckboxListTile Radio RadioListTile Slider
TabBar TabBarView TabController DefaultTabController Drawer SafeArea MediaQuery
AnimationController Animation Tween CurvedAnimation Curves AnimatedContainer AnimatedOpacity
FutureBuilder StreamBuilder ValueListenableBuilder LayoutBuilder Builder OrientationBuilder
BoxDecoration BoxConstraints ConstrainedBox BorderRadius Border BoxShadow Offset Size Rect
Alignment Matrix4 Transform Opacity ClipRRect ClipOval Material Ink Tooltip Hero
Clipboard ClipboardData HapticFeedback SystemChrome SystemUiOverlayStyle
DateFormat NumberFormat Intl Random Completer StringBuffer RegExp Match
ConsumerWidget ConsumerState ConsumerStatefulWidget WidgetRef Ref Provider StateProvider
StateNotifier StateNotifierProvider FutureProvider StreamProvider ChangeNotifier
AsyncValue ProviderScope UncontrolledProviderScope ProviderContainer AutoDisposeProvider
GoRoute GoRouter ShellRoute StatefulShellRoute MaterialPage NoTransitionPage
Share XFile ShareResult LaunchMode PointerDeviceKind MaterialScrollBehavior ScrollBehavior
SearchDelegate ThemeMode Locale TextDirection ValueChanged VoidCallback AsyncCallback
InputBorder OutlineInputBorder UnderlineInputBorder FloatingLabelBehavior TextInputType
CrossAxisAlignment MainAxisAlignment MainAxisSize FlexFit StackFit BoxFit
WidgetsBinding WidgetsFlutterBinding SchedulerBinding PlatformDispatcher FlutterError
Brightness Typography TextTheme ColorScheme IconData IconThemeData AppBarTheme
Comparable Comparator num Function dynamic void Null Never
'''.split())

problems = collections.defaultdict(list)

for f, t in src.items():
    # импортированные локальные файлы
    imports = set()
    for m in re.finditer(r"import\s+'([^']+)'", t):
        p = m.group(1)
        if p.startswith('package:') or p.startswith('dart:'):
            imports.add(p)
        else:
            try:
                imports.add(str((f.parent / p).resolve().relative_to(pathlib.Path('.').resolve())))
            except Exception:
                pass
    # типы, использованные в файле (заглавная буква, не в строках/комментариях)
    body = re.sub(r'//.*', '', t)
    body = re.sub(r'/\*[\s\S]*?\*/', '', body)
    body = re.sub(r"'[^'\n]*'", "''", body)
    body = re.sub(r'"[^"\n]*"', '""', body)
    used = set(re.findall(r'\b([A-Z][A-Za-z0-9_]{2,})\b', body))
    own = set(re.findall(r'^(?:abstract\s+|sealed\s+)*(?:class|enum|mixin|extension|typedef)\s+(\w+)', t, re.M))
    for u in used:
        if u in SDK or u in own: continue
        if u.startswith('_'): continue
        if u not in defined: continue          # внешний пакет — пропускаем
        target = defined[u]
        if target == f: continue
        # тип определён в проекте — проверим, импортирован ли его файл
        if str(target) not in imports:
            # возможно, импортирован через реэкспорт (часто для моделей/БД)
            problems[str(f)].append(f"тип {u} (определён в {target}) — файл не импортирован напрямую")

print("=== ПРОВЕРКА ИМПОРТОВ ТИПОВ ===")
cnt = 0
for f, ps in sorted(problems.items()):
    uniq = sorted(set(ps))
    cnt += len(uniq)
    print(f"\n{f}:")
    for p in uniq[:6]:
        print(f"   {p}")
print(f"\nВсего подозрений: {cnt}")
