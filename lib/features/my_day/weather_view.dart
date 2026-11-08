// lib/features/my_day/weather_view.dart
// Погода в «Моём дне» (1.15.1, просьба владельца 07.11.2026): значок и
// температура в карточке «Сейчас», по нажатию — прогноз по часам, источник
// данных, смена города и выключение. Город — поиском (GeoNames на сервере Ogneliss), без
// местоположения телефона. Данные — services/weather/weather_service.dart.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../data/providers/shared_prefs_provider.dart';
import '../../l10n/app_localizations.dart';
import '../../services/security/managed_config.dart';
import '../../services/weather/weather_service.dart';
import '../../widgets/common/app_sheet.dart';

IconData weatherIcon(WeatherKind? k, {bool night = false}) => switch (k) {
      WeatherKind.clear => night ? AppIcons.clear_night : AppIcons.clear_day,
      WeatherKind.fair || WeatherKind.partlyCloudy => night ? AppIcons.partly_cloudy_night : AppIcons.partly_cloudy_day,
      WeatherKind.cloudy => AppIcons.cloud,
      WeatherKind.fog => AppIcons.foggy,
      WeatherKind.lightRain => AppIcons.rainy_light,
      WeatherKind.rain => AppIcons.rainy,
      WeatherKind.heavyRain => AppIcons.rainy_heavy,
      WeatherKind.sleet => AppIcons.weather_mix,
      WeatherKind.snow => AppIcons.weather_snowy,
      WeatherKind.thunder => AppIcons.thunderstorm,
      null => AppIcons.cloud,
    };

String weatherLabel(WeatherKind? k, AppLocalizations l10n) => k == null
    ? ''
    : l10n.tr(switch (k) {
        WeatherKind.clear => 'weatherClear',
        WeatherKind.fair => 'weatherFair',
        WeatherKind.partlyCloudy => 'weatherPartlyCloudy',
        WeatherKind.cloudy => 'weatherCloudy',
        WeatherKind.fog => 'weatherFog',
        WeatherKind.lightRain => 'weatherLightRain',
        WeatherKind.rain => 'weatherRain',
        WeatherKind.heavyRain => 'weatherHeavyRain',
        WeatherKind.sleet => 'weatherSleet',
        WeatherKind.snow => 'weatherSnow',
        WeatherKind.thunder => 'weatherThunder',
      });

/// «+3°», «−2°», «0°» — со знаком, как в прогнозах.
String temperatureText(double t) {
  final r = t.round();
  if (r == 0) return '0°';
  return r > 0 ? '+$r°' : '−${-r}°';
}

/// Можно ли показывать погоду (не запрещена организацией).
bool weatherAllowed(WidgetRef ref) =>
    ref.watch(weatherApprovedProvider) && !ref.watch(managedPolicyProvider).blockWeather;

/// «17:22» сегодня, «6 нояб., 17:22» — в другой день.
String _when(DateTime at, AppLocalizations l10n) {
  final now = DateTime.now();
  final today = at.year == now.year && at.month == now.month && at.day == now.day;
  return today ? DateFormat('HH:mm').format(at) : DateFormat('d MMM, HH:mm', l10n.localeCode).format(at);
}

/// Подпись источника со ссылкой на условия (CC BY 4.0 — «provide a link to
/// the license»; GeoNames — CC BY 4.0, ссылка на сайт).
class _SourceLink extends StatelessWidget {
  final String text;
  final String url;
  const _SourceLink(this.text, this.url);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      link: true,
      child: InkWell(
        onTap: () => unawaited(launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.xs),
          child: Text(text,
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppColors.mutedText(context),
                decoration: TextDecoration.underline,
                decorationColor: AppColors.mutedText(context),
              )),
        ),
      ),
    );
  }
}

/// Значок и температура для карточки «Сейчас»; нажатие — окно погоды.
/// Погода выключена — ничего.
class WeatherChip extends ConsumerWidget {
  const WeatherChip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(weatherSettingsProvider);
    if (!settings.active || !weatherAllowed(ref)) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final f = ref.watch(weatherProvider).value;
    final label = f == null
        ? l10n.tr('weather')
        : '${settings.place!.name}: ${temperatureText(f.now.temp)}, ${weatherLabel(f.now.kind, l10n)}';
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: Radii.chipAll,
        onTap: () => showWeatherSheet(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.s, vertical: Space.xs),
          child: f == null
              ? Icon(AppIcons.cloud, size: 22, color: AppColors.mutedText(context))
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(weatherIcon(f.now.kind, night: f.now.night), size: 26, color: theme.colorScheme.primary),
                  const SizedBox(width: Space.xs),
                  Text(temperatureText(f.now.temp),
                      style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
                ]),
        ),
      ),
    );
  }
}

/// Окно погоды: сейчас, сегодня, по часам, источник; сменить город,
/// выключить. Погода не включена — сразу выбор города.
Future<void> showWeatherSheet(BuildContext context) async {
  final container = ProviderScope.containerOf(context);
  if (!container.read(weatherSettingsProvider).active) {
    await showWeatherPlacePicker(context);
    return;
  }
  await showAppSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _WeatherSheet(),
  );
}

class _WeatherSheet extends ConsumerWidget {
  const _WeatherSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final settings = ref.watch(weatherSettingsProvider);
    final async = ref.watch(weatherProvider);
    final place = settings.place;
    final f = async.value;
    final muted = AppColors.mutedText(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.l),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(place == null ? l10n.tr('weather') : place.name, style: theme.textTheme.titleLarge),
        if (place != null && place.region.isNotEmpty)
          Text(place.region, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
        const SizedBox(height: Space.m),
        if (f == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.l),
            child: async.isLoading
                ? const Center(child: CircularProgressIndicator())
                : Text(l10n.tr('weatherUnavailable'), style: TextStyle(color: muted)),
          )
        else ...[
          Row(children: [
            Icon(weatherIcon(f.now.kind, night: f.now.night), size: 44, color: theme.colorScheme.primary),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(temperatureText(f.now.temp), style: theme.textTheme.headlineMedium),
                Text(
                  [
                    weatherLabel(f.now.kind, l10n),
                    l10n
                        .tr('weatherTodayRange')
                        .replaceAll('{min}', temperatureText(f.min))
                        .replaceAll('{max}', temperatureText(f.max)),
                  ].where((s) => s.isNotEmpty).join(' · '),
                  style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                ),
              ]),
            ),
          ]),
          if (f.hours.isNotEmpty) ...[
            const SizedBox(height: Space.m),
            SizedBox(
              height: 84,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: f.hours.length,
                separatorBuilder: (_, __) => const SizedBox(width: Space.m),
                itemBuilder: (_, i) {
                  final h = f.hours[i];
                  return Semantics(
                    label: '${DateFormat('HH:mm').format(h.at)}, ${temperatureText(h.temp)}, ${weatherLabel(h.kind, l10n)}',
                    excludeSemantics: true,
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(DateFormat('HH:mm').format(h.at), style: theme.textTheme.labelMedium?.copyWith(color: muted)),
                      const SizedBox(height: Space.xs),
                      Icon(weatherIcon(h.kind, night: h.night), size: 24, color: theme.colorScheme.primary),
                      const SizedBox(height: Space.xs),
                      Text(temperatureText(h.temp), style: theme.textTheme.labelLarge),
                    ]),
                  );
                },
              ),
            ),
          ],
        ],
        const SizedBox(height: Space.s),
        if (f?.fetchedAt case final at?)
          Text(l10n.tr('weatherFetchedAt').replaceAll('{time}', _when(at, l10n)),
              style: theme.textTheme.labelSmall?.copyWith(color: muted)),
        _SourceLink(l10n.tr('weatherMetAttribution'), 'https://api.met.no/doc/License'),
        const SizedBox(height: Space.m),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(AppIcons.location_on, size: 18),
              label: Text(l10n.tr('weatherChangePlace')),
              onPressed: () {
                Navigator.of(context).pop();
                unawaited(showWeatherPlacePicker(context));
              },
            ),
          ),
          const SizedBox(width: Space.s),
          Expanded(
            child: TextButton(
              onPressed: () {
                unawaited(ref.read(weatherSettingsProvider.notifier).turnOff());
                Navigator.of(context).pop();
              },
              child: Text(l10n.tr('weatherTurnOff')),
            ),
          ),
        ]),
      ]),
    );
  }
}

/// Выбор города: поиск по нажатию «Найти» (как было с OpenStreetMap — не
/// подсказки на каждую букву), список найденного.
Future<void> showWeatherPlacePicker(BuildContext context) => showAppSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _PlacePicker(),
    );

class _PlacePicker extends ConsumerStatefulWidget {
  const _PlacePicker();

  @override
  ConsumerState<_PlacePicker> createState() => _PlacePickerState();
}

class _PlacePickerState extends ConsumerState<_PlacePicker> {
  final _query = TextEditingController();
  List<WeatherPlace>? _found;
  bool _busy = false;
  bool _failed = false;
  bool _off = false;
  DateTime? _last;

  /// Найденное за время работы приложения: тот же запрос — без сети.
  static final _memo = <String, List<WeatherPlace>>{};

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _query.text.trim();
    if (q.isEmpty || _busy) return;
    // Не чаще раза в секунду (бережём сервер Ogneliss).
    final last = _last;
    if (last != null && DateTime.now().difference(last) < const Duration(seconds: 1)) return;
    _last = DateTime.now();
    final lang = AppLocalizations.of(context).localeCode;
    final memoKey = '$lang\u0000${q.toLowerCase()}';
    final known = _memo[memoKey];
    if (known != null) {
      setState(() {
        _found = known;
        _failed = _off = false;
      });
      return;
    }
    setState(() {
      _busy = true;
      _failed = _off = false;
    });
    try {
      final client = ref.read(weatherHttpProvider);
      final ends = await WeatherEndpoints.load(ref.read(sharedPrefsProvider), client);
      if (ends.geocoder.isEmpty) {
        if (mounted) setState(() => _off = true);
        return;
      }
      final found = await WeatherApi.search(client, q, lang, url: ends.geocoder);
      if (_memo.length >= 30) _memo.remove(_memo.keys.first);
      _memo[memoKey] = found;
      if (!mounted) return;
      setState(() => _found = found);
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final muted = AppColors.mutedText(context);
    final found = _found;
    return Padding(
      padding: EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.l + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(l10n.tr('weatherSearchTitle'), style: theme.textTheme.titleLarge),
        const SizedBox(height: Space.xs),
        Text(l10n.tr('weatherSearchNote'), style: theme.textTheme.bodySmall?.copyWith(color: muted)),
        const SizedBox(height: Space.m),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _query,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => unawaited(_search()),
              decoration: InputDecoration(hintText: l10n.tr('weatherSearchHint'), isDense: true),
            ),
          ),
          const SizedBox(width: Space.s),
          FilledButton(
            onPressed: _busy ? null : () => unawaited(_search()),
            child: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(l10n.tr('weatherSearch')),
          ),
        ]),
        if (_off)
          Padding(
            padding: const EdgeInsets.only(top: Space.m),
            child: Text(l10n.tr('weatherSearchOff'), style: TextStyle(color: muted)),
          )
        else if (_failed)
          Padding(
            padding: const EdgeInsets.only(top: Space.m),
            child: Text(l10n.tr('weatherSearchFailed'), style: TextStyle(color: AppColors.errorText(context))),
          )
        else if (found != null && found.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: Space.m),
            child: Text(l10n.tr('weatherNotFound'), style: TextStyle(color: muted)),
          )
        else if (found != null)
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final p in found)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(AppIcons.location_on),
                    title: Text(p.name),
                    subtitle: p.region.isEmpty ? null : Text(p.region),
                    onTap: () async {
                      await ref.read(weatherSettingsProvider.notifier).setPlace(p);
                      if (context.mounted) Navigator.of(context).pop();
                    },
                  ),
              ],
            ),
          ),
        const SizedBox(height: Space.s),
        _SourceLink(l10n.tr('weatherCitiesAttribution'), 'https://www.geonames.org/'),
      ]),
    );
  }
}
