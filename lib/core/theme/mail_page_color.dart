// lib/core/theme/mail_page_color.dart
import 'package:flutter/material.dart';

/// «Тёплый фон письма» (Настройки → Общие): слегка кремовый вместо чисто
/// белого в светлой теме — мягче для глаз при долгом чтении. Задаётся в
/// main.dart из настроек.
bool mailPageWarm = false;

/// Тёплый белый: контраст основного текста (#1A1F26) — 15.6:1.
const mailPageWarmColor = Color(0xFFFBF8F2);

/// Фон страницы письма и редактора: белый (или тёплый белый) в светлой теме,
/// фон темы в тёмной и AMOLED. Письмо и поле вокруг — одного цвета (раньше
/// письмо было белой карточкой на сером фоне в любой теме).
Color mailPageColor(ThemeData theme) => theme.brightness == Brightness.light
    ? (mailPageWarm ? mailPageWarmColor : Colors.white)
    : theme.scaffoldBackgroundColor;
