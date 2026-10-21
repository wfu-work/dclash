import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/widgets/app_icon.dart';
import '../../app/widgets/app_system_ui.dart';
import 'app_typography.dart';

abstract final class AppSpace {
  static const page = 24.0, gap = 16.0, compact = 8.0;
}

abstract final class AppShapes {
  static const small = RoundedSuperellipseBorder(
    borderRadius: BorderRadius.all(Radius.circular(5)),
  );
  static const card = RoundedSuperellipseBorder(
    borderRadius: BorderRadius.all(Radius.circular(11)),
  );
  static const control = RoundedSuperellipseBorder(
    borderRadius: BorderRadius.all(Radius.circular(7)),
  );
  static const workspace = RoundedSuperellipseBorder(
    borderRadius: BorderRadius.all(Radius.circular(16)),
  );
  static const pill = RoundedSuperellipseBorder(
    borderRadius: BorderRadius.all(Radius.circular(100)),
  );
}

@immutable
class AppSurfaces extends ThemeExtension<AppSurfaces> {
  const AppSurfaces({required this.window, required this.sidebar});
  final Color window, sidebar;

  @override
  AppSurfaces copyWith({Color? window, Color? sidebar}) => AppSurfaces(
    window: window ?? this.window,
    sidebar: sidebar ?? this.sidebar,
  );

  @override
  AppSurfaces lerp(AppSurfaces? other, double t) => other == null
      ? this
      : AppSurfaces(
          window: Color.lerp(window, other.window, t)!,
          sidebar: Color.lerp(sidebar, other.sidebar, t)!,
        );
}

abstract final class AppTheme {
  static const accents = <String, Color>{
    'blue': Color(0xFF246FE5),
    'purple': Color(0xFF7654C8),
    'green': Color(0xFF167A59),
    'orange': Color(0xFFB9601C),
    'pink': Color(0xFFB43B76),
  };

  static ThemeData resolve(
    Brightness brightness,
    String accent, {
    bool pureBlack = false,
    String fontFamily = 'system',
  }) {
    final dark = brightness == Brightness.dark;
    final primary = accents[accent] ?? accents['blue']!;
    final surface = dark
        ? pureBlack
              ? Colors.black
              : const Color(0xFF252629)
        : const Color(0xFFF8F8F8);
    final card = dark
        ? pureBlack
              ? const Color(0xFF121416)
              : const Color(0xFF2B2C30)
        : Colors.white;
    final foreground = dark ? const Color(0xFFF1F1F2) : const Color(0xFF262729);
    final secondary = dark ? const Color(0xFFC8C9CC) : const Color(0xFF606166);
    final muted = dark ? const Color(0xFFA7A8AD) : const Color(0xFF6B6C71);
    final workspace = dark
        ? pureBlack
              ? Colors.black
              : const Color(0xFF202124)
        : const Color(0xFFF2F3F4);
    final surfaceSubtle = dark
        ? const Color(0xFF303135)
        : const Color(0xFFEEEEF0);
    final selection = dark ? const Color(0xFF3A3B40) : const Color(0xFFE7E7E9);
    final colors =
        ColorScheme.fromSeed(
          seedColor: primary,
          brightness: brightness,
        ).copyWith(
          primary: dark ? Color.lerp(primary, Colors.white, .32) : primary,
          onPrimary: dark ? const Color(0xFF111B2D) : Colors.white,
          primaryContainer: selection,
          onPrimaryContainer: foreground,
          secondary: secondary,
          onSecondary: card,
          secondaryContainer: surfaceSubtle,
          onSecondaryContainer: foreground,
          error: dark ? const Color(0xFFE1807D) : const Color(0xFFC2413D),
          surface: surface,
          onSurface: foreground,
          onSurfaceVariant: secondary,
          surfaceTint: Colors.transparent,
          surfaceContainerLowest: workspace,
          surfaceContainerLow: surface,
          surfaceContainer: surfaceSubtle,
          surfaceContainerHigh: card,
          surfaceContainerHighest: selection,
          outline: dark ? const Color(0xFF58595F) : const Color(0xFFC9CACD),
          outlineVariant: dark
              ? const Color(0xFF3E3F44)
              : const Color(0xFFDDDEE0),
        );
    final nativeFont = switch (defaultTargetPlatform) {
      TargetPlatform.macOS => '.AppleSystemUIFont',
      TargetPlatform.iOS => '.SF UI Text',
      TargetPlatform.windows => 'Segoe UI',
      TargetPlatform.android => 'Roboto',
      _ => 'Noto Sans',
    };
    final fallbacks = switch (defaultTargetPlatform) {
      TargetPlatform.macOS || TargetPlatform.iOS => const ['PingFang SC'],
      TargetPlatform.windows => const ['Microsoft YaHei UI', 'Microsoft YaHei'],
      _ => const ['Noto Sans CJK SC', 'Noto Sans SC', 'sans-serif'],
    };
    final family = fontFamily == 'system' ? nativeFont : fontFamily;
    final text = AppTypography.resolve(
      foreground,
      secondary,
    ).apply(fontFamily: family, fontFamilyFallback: fallbacks);
    final border = BorderSide(color: colors.outlineVariant, width: .5);
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(7),
      borderSide: border,
    );
    final buttonStyle = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(40, 40)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
      shape: const WidgetStatePropertyAll(AppShapes.control),
      textStyle: WidgetStatePropertyAll(text.labelLarge),
      iconSize: const WidgetStatePropertyAll(16),
      elevation: const WidgetStatePropertyAll(0),
    );
    final contrastButtonStyle = buttonStyle.copyWith(
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? colors.onSurface.withValues(alpha: .12)
            : dark
            ? Colors.white
            : Colors.black,
      ),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? colors.onSurfaceVariant
            : dark
            ? Colors.black
            : Colors.white,
      ),
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colors,
      fontFamily: family,
      fontFamilyFallback: fallbacks,
      textTheme: text,
      scaffoldBackgroundColor: workspace,
      canvasColor: card,
      extensions: [
        AppSurfaces(
          window: dark
              ? pureBlack
                    ? Colors.black
                    : const Color(0xFF202124)
              : const Color(0xFFF2F3F4),
          sidebar: dark
              ? pureBlack
                    ? Colors.black
                    : const Color(0xFF202124)
              : const Color(0xFFF2F3F4),
        ),
      ],
      splashFactory: NoSplash.splashFactory,
      hoverColor: surfaceSubtle,
      focusColor: selection,
      highlightColor: selection,
      iconTheme: IconThemeData(size: 20, color: foreground),
      primaryIconTheme: IconThemeData(size: 20, color: foreground),
      actionIconTheme: ActionIconThemeData(
        backButtonIconBuilder: (_) => const AppIcon(AppIcons.arrowLeft),
        closeButtonIconBuilder: (_) => const AppIcon(AppIcons.close),
        drawerButtonIconBuilder: (_) => const AppIcon(AppIcons.menu),
        endDrawerButtonIconBuilder: (_) => const AppIcon(AppIcons.menu),
      ),
      appBarTheme: AppBarThemeData(
        backgroundColor: workspace,
        foregroundColor: foreground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: text.titleLarge,
        systemOverlayStyle: AppSystemUi.styleFor(brightness),
      ),
      cardTheme: CardThemeData(
        color: card,
        surfaceTintColor: Colors.transparent,
        shape: AppShapes.card.copyWith(side: border),
        elevation: 0,
        margin: EdgeInsets.zero,
      ),
      dividerTheme: DividerThemeData(
        color: colors.outlineVariant,
        thickness: .5,
        space: 1,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        shape: AppShapes.workspace.copyWith(side: border),
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyMedium,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: card,
        surfaceTintColor: Colors.transparent,
        shape: AppShapes.workspace,
        showDragHandle: true,
        dragHandleSize: const Size(32, 3),
        dragHandleColor: colors.outline,
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: card,
        isDense: true,
        hintStyle: text.bodyMedium?.copyWith(color: muted),
        labelStyle: text.bodySmall?.copyWith(
          color: secondary,
          fontWeight: FontWeight.w500,
        ),
        prefixIconColor: secondary,
        suffixIconColor: secondary,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        border: inputBorder,
        enabledBorder: inputBorder,
        disabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: colors.primary, width: 1),
        ),
        errorBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: colors.error),
        ),
        focusedErrorBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: colors.error),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(style: contrastButtonStyle),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: buttonStyle.copyWith(side: WidgetStatePropertyAll(border)),
      ),
      textButtonTheme: TextButtonThemeData(style: buttonStyle),
      elevatedButtonTheme: ElevatedButtonThemeData(style: buttonStyle),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          shape: AppShapes.control,
          minimumSize: const Size(40, 40),
          iconSize: 20,
          foregroundColor: foreground,
          disabledForegroundColor: secondary.withValues(alpha: .45),
          highlightColor: colors.surfaceContainer,
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: secondary,
        titleTextStyle: text.bodyMedium,
        subtitleTextStyle: text.bodySmall?.copyWith(color: muted),
        minLeadingWidth: 20,
        horizontalTitleGap: 12,
        minTileHeight: 44,
        shape: AppShapes.control,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: card,
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        shadowColor: Colors.black.withValues(alpha: dark ? .30 : .10),
        shape: AppShapes.card.copyWith(side: border),
        textStyle: text.bodyMedium,
        menuPadding: const EdgeInsets.all(4),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colors.surfaceContainerLow,
        selectedColor: colors.primaryContainer,
        labelStyle: text.labelMedium,
        secondaryLabelStyle: text.labelMedium?.copyWith(color: colors.primary),
        shape: AppShapes.control,
        side: BorderSide.none,
        showCheckmark: false,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: const WidgetStatePropertyAll(AppShapes.control),
          side: const WidgetStatePropertyAll(BorderSide.none),
          textStyle: WidgetStatePropertyAll(text.labelMedium),
          iconSize: const WidgetStatePropertyAll(16),
          minimumSize: const WidgetStatePropertyAll(Size(44, 36)),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? colors.primaryContainer
                : colors.surfaceContainerLow,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? colors.primary
                : secondary,
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        materialTapTargetSize: MaterialTapTargetSize.padded,
        padding: EdgeInsets.zero,
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return colors.onSurface.withValues(alpha: .38);
          }
          return states.contains(WidgetState.selected)
              ? colors.onPrimary
              : colors.surface;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return colors.onSurface.withValues(alpha: .12);
          }
          return states.contains(WidgetState.selected)
              ? colors.primary
              : colors.surfaceContainerHighest;
        }),
        trackOutlineWidth: const WidgetStatePropertyAll(0),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: colors.primary,
        selectionColor: colors.primary.withValues(alpha: .2),
        selectionHandleColor: colors.primary,
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 450),
        textStyle: text.labelSmall?.copyWith(color: colors.onInverseSurface),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        strokeWidth: 1.5,
      ),
    );
  }
}
