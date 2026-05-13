# URA CORE Design System - Reusable Widgets

## Overview
This directory contains reusable widget components built on top of the URA CORE design system foundation. All widgets follow Material Design 3 guidelines and support RTL for Arabic language.

## Widget Categories

### Button Components (`buttons/`)
- **[`app_button.dart`](buttons/app_button.dart)** - Primary button with variants (elevated, outlined, text)
  - Loading state support
  - Icon support
  - Customizable colors and dimensions
  - Validation integration

- **[`app_icon_button.dart`](buttons/app_icon_button.dart)** - Icon button with variants
  - Filled, outlined, and text variants
  - Tooltip support
  - Customizable size and colors

- **[`app_floating_action_button.dart`](buttons/app_floating_action_button.dart)** - FAB with variants
  - Standard and extended FAB support
  - Customizable styling

### Input Components (`inputs/`)
- **[`app_text_field.dart`](inputs/app_text_field.dart)** - Text input with validation
  - Built-in validation
  - Prefix/suffix icons
  - Character counter
  - Password visibility toggle
  - RTL support

- **[`app_dropdown_field.dart`](inputs/app_dropdown_field.dart)** - Dropdown selector
  - Custom items builder
  - Validation support
  - Prefix icon support

- **[`app_search_field.dart`](inputs/app_search_field.dart)** - Search input field
  - Built-in clear button
  - Real-time filtering
  - Search icon

- **[`app_text_area.dart`](inputs/app_text_area.dart)** - Multi-line text input
  - Character counter
  - Validation support
  - Customizable height

### Card Components (`cards/`)
- **[`app_card.dart`](cards/app_card.dart)** - Basic card with elevation
  - Customizable elevation
  - Border radius options
  - Clickable support
  - Shadow customization

- **[`app_list_tile.dart`](cards/app_list_tile.dart)** - List tile with leading/trailing
  - Three-line support
  - Tap and long-press handling
  - Divider support

- **[`app_info_card.dart`](cards/app_info_card.dart)** - Information display card
  - Status-based coloring (success, error, warning, info)
  - Action button support
  - Dismissible option

### Layout Components (`layout/`)
- **[`app_scaffold.dart`](layout/app_scaffold.dart)** - Scaffold with consistent structure
  - Consistent padding
  - Safe area handling
  - Bottom navigation support

- **[`app_sliver_app_bar.dart`](layout/app_sliver_app_bar.dart)** - Custom app bar with scroll behavior
  - Scroll behavior
  - Customizable actions
  - Flexible space support

- **[`app_section.dart`](layout/app_section.dart)** - Section with title and content
  - Optional title and subtitle
  - Action button support
  - Divider support

- **[`app_empty_state.dart`](layout/app_empty_state.dart)** - Empty state placeholder
  - Icon support
  - Action button support
  - Customizable message

- **[`app_loading_state.dart`](layout/app_loading_state.dart)** - Loading state indicator
  - Progress indicator
  - Customizable message

### Feedback Components (`feedback/`)
- **[`app_loading_indicator.dart`](feedback/app_loading_indicator.dart)** - Loading spinner
  - Customizable size and color
  - Optional background overlay

- **[`app_error_view.dart`](feedback/app_error_view.dart)** - Error display with retry
  - Error message and description
  - Retry button
  - Customizable icon

- **[`app_success_view.dart`](feedback/app_success_view.dart)** - Success message display
  - Success message and description
  - Action button support
  - Customizable icon

- **[`app_snackbar.dart`](feedback/app_snackbar.dart)** - Custom snackbar variants
  - Multiple variants (success, error, warning, info)
  - Action button support
  - Dismissible

### Navigation Components (`navigation/`)
- **[`app_bottom_nav_bar.dart`](navigation/app_bottom_nav_bar.dart)** - Bottom navigation bar
  - Customizable items
  - Label visibility options
  - Material Design 3 styling

- **[`app_tab_bar.dart`](navigation/app_tab_bar.dart)** - Tab bar for top navigation
  - Customizable tabs
  - Indicator customization
  - Scrollable support

- **[`app_back_button.dart`](navigation/app_back_button.dart)** - Back button with custom action
  - Custom icon
  - Custom action
  - Tooltip support

## Usage

Import all widgets using the barrel export:
```dart
import 'package:ura_core/core/design_system/widgets/widgets.dart';
```

Or import specific widgets:
```dart
import 'package:ura_core/core/design_system/widgets/buttons/app_button.dart';
```

## Design System Integration

All widgets use:
- **Colors**: [`AppColors`](../theme/colors/app_colors.dart)
- **Typography**: [`AppTextStyles`](../theme/typography/text_styles.dart)
- **Spacing**: [`AppSpacing`](../theme/spacing/app_spacing.dart)
- **Constants**: [`AppConstants`](../theme/constants/app_constants.dart)

## Features

- ✅ RTL support for Arabic language
- ✅ Material Design 3 guidelines
- ✅ Consistent API across similar widgets
- ✅ Proper accessibility support
- ✅ Clear visual feedback for interactions
- ✅ Responsive design considerations
- ✅ Form validation support where applicable
- ✅ BLoC state management integration ready

## Widget Design Principles

1. **Single Responsibility**: Each widget has a single, well-defined purpose
2. **Consistent API**: Similar widgets have consistent parameter naming
3. **Customizability**: All widgets are customizable through parameters
4. **Accessibility**: Proper semantic labels and support
5. **Documentation**: Comprehensive documentation comments

## Status

✅ All widgets created and functional
✅ Barrel export file created
✅ Design system integration complete
✅ RTL support implemented
✅ Material Design 3 compliant

## Next Steps

1. Refactor existing screens to use new design system widgets
2. Migrate styling references to centralized system
3. Verify UI remains visually identical
4. Add unit tests for widgets
5. Create widget storybook/documentation
