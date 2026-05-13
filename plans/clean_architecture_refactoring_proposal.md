# URA CORE - Clean Architecture Refactoring Proposal

## Executive Summary

This document outlines a comprehensive refactoring plan for the URA CORE Flutter application to implement Clean Architecture principles and a centralized design system. The refactoring will maintain the current UI and behavior while improving code maintainability, scalability, and consistency.

---

## 1. Current Structure Analysis

### 1.1 Current Directory Structure

```
lib/
├── app.dart
├── main.dart
├── config/
│   └── supabase_config.dart
├── core/
│   ├── di/
│   │   └── injection.dart
│   ├── errors/
│   │   ├── app_error.dart
│   │   ├── app_result.dart
│   │   └── error_handler.dart
│   ├── logging/
│   │   └── app_logger.dart
│   └── notifications/
│       ├── notification_dispatcher.dart
│       └── notification_service.dart
├── features/
│   ├── auth/
│   │   ├── data/
│   │   │   └── auth_repository.dart
│   │   ├── logic/
│   │   │   ├── auth_cubit.dart
│   │   │   └── auth_state.dart
│   │   └── ui/
│   │       ├── login_screen.dart
│   │       ├── register_screen.dart
│   │       ├── pending_approval_screen.dart
│   │       ├── forgot_password_screen.dart
│   │       └── reset_password_screen.dart
│   ├── verifier/
│   │   ├── data/
│   │   │   ├── entity_repository.dart
│   │   │   ├── inventory_repository.dart
│   │   │   ├── order_repository.dart
│   │   │   └── order_template_repository.dart
│   │   ├── logic/
│   │   │   ├── create_order_cubit.dart
│   │   │   ├── edit_order_cubit.dart
│   │   │   ├── order_templates_cubit.dart
│   │   │   ├── orders_cubit.dart
│   │   │   ├── orders_state.dart
│   │   │   └── pending_users_cubit.dart
│   │   └── ui/
│   │       ├── create_order_screen.dart
│   │       ├── edit_order_screen.dart
│   │       ├── verifier_home_screen.dart
│   │       └── widgets/
│   │           ├── add_item_sheet.dart
│   │           ├── order_card.dart
│   │           └── templates_sheet.dart
│   ├── manager/
│   ├── rep/
│   ├── storage/
│   ├── inventory/
│   ├── chat/
│   ├── notifications/
│   ├── entities/
│   └── profile/
├── router/
│   └── app_router.dart
└── shared/
    ├── models/
    │   ├── app_notification.dart
    │   ├── audit_log_entry.dart
    │   ├── chat_message.dart
    │   ├── chat_thread.dart
    │   ├── draft_order_item.dart
    │   ├── entity.dart
    │   ├── inventory_audit_log_entry.dart
    │   ├── inventory_item.dart
    │   ├── order_edit_log_entry.dart
    │   ├── order_item.dart
    │   ├── order_template.dart
    │   ├── order.dart
    │   └── profile.dart
    ├── widgets/
    │   ├── order_list_tile.dart
    │   └── receipt_viewer_screen.dart
    └── order_status_theme.dart
```

### 1.2 Identified Issues

#### 1.2.1 Architecture Issues

**1. Missing Clean Architecture Layers**
- No clear separation between domain, data, and presentation layers
- Models are in `lib/shared/models/` but should be in domain layer
- No use cases layer (business logic is embedded in cubits)
- Repositories mix business logic with data access
- Cubits directly depend on repositories without use cases

**2. Tight Coupling**
- Features have direct dependencies on shared models
- No clear dependency flow between layers
- UI layer directly accesses data repositories through cubits
- Business logic is scattered across cubits and repositories

**3. Feature Organization Issues**
- Some features lack proper layer separation (e.g., entities only has logic/ui)
- Inconsistent structure across features
- No clear boundaries between features

**4. Dependency Injection**
- All dependencies registered in a single file (`injection.dart`)
- No clear grouping or organization of dependencies
- Mix of singleton and factory registrations without clear rationale

#### 1.2.2 Styling and Design System Issues

**1. Hardcoded Values Throughout Screens**
```dart
// Examples from login_screen.dart
padding: const EdgeInsets.all(24),
constraints: const BoxConstraints(maxWidth: 400),
style: const TextStyle(
  fontSize: 28,
  fontWeight: FontWeight.bold,
),
const SizedBox(height: 32),
```

**2. No Centralized Theming System**
- Only one theming file: `order_status_theme.dart` for order status colors
- Basic theme in `app.dart` with minimal customization:
```dart
theme: ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
  useMaterial3: true,
  textTheme: GoogleFonts.tajawalTextTheme(),
),
```

**3. Duplicated Styling Logic**
- Similar card styles repeated across multiple screens
- Button styles duplicated in multiple locations
- Input decoration styles repeated
- Text styles hardcoded in each screen

**4. No Consistent Spacing System**
- Hardcoded spacing values: `EdgeInsets.all(24)`, `SizedBox(height: 32)`
- No spacing constants or design tokens
- Inconsistent spacing patterns across screens

**5. No Centralized Typography System**
- Text styles defined inline in each screen
- No reusable text style definitions
- Font sizes and weights scattered throughout codebase
- No clear typography hierarchy

**6. Missing Design Tokens**
- No color constants beyond order status
- No border radius constants
- No elevation constants
- No animation duration constants

**7. Inconsistent Color Usage**
- Colors used directly: `Colors.teal`, `Colors.red`, `Colors.amber`
- No semantic color naming (success, error, warning, info)
- No dark mode support structure

#### 1.2.3 Code Quality Issues

**1. Mixed Concerns**
- UI components contain business logic
- State management mixed with UI rendering
- Navigation logic embedded in screens

**2. Limited Reusability**
- Widgets are tightly coupled to specific features
- No shared widget library
- Repeated patterns instead of reusable components

**3. Testing Challenges**
- Tight coupling makes unit testing difficult
- Business logic embedded in cubits is hard to test in isolation
- No clear boundaries for test doubles

---

## 2. Proposed New Clean Architecture Structure

### 2.1 Architecture Overview

The proposed architecture follows Clean Architecture principles with clear separation of concerns and dependency flow:

```
┌─────────────────────────────────────────────────────────────┐
│                     Presentation Layer                       │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  UI (Screens, Widgets)                                │  │
│  │  - Stateless widgets                                   │  │
│  │  - Screen composition                                  │  │
│  │  - User interactions                                   │  │
│  └───────────────────────────────────────────────────────┘  │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  State Management (Cubits/BLoCs)                       │  │
│  │  - State holding                                      │  │
│  │  - Event handling                                     │  │
│  │  - UI state transformations                           │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                            ↓ depends on
┌─────────────────────────────────────────────────────────────┐
│                      Domain Layer                            │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  Entities (Business Models)                           │  │
│  │  - Core business objects                              │  │
│  │  - Business rules                                     │  │
│  └───────────────────────────────────────────────────────┘  │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  Use Cases (Interactors)                              │  │
│  │  - Business logic                                     │  │
│  │  - Application-specific rules                        │  │
│  │  - Orchestrate data flow                             │  │
│  └───────────────────────────────────────────────────────┘  │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  Repository Interfaces                                │  │
│  │  - Data access contracts                              │  │
│  │  - Domain defines requirements                        │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                            ↓ depends on
┌─────────────────────────────────────────────────────────────┐
│                       Data Layer                              │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  Repository Implementations                            │  │
│  │  - Supabase data access                                │  │
│  │  - Local storage                                       │  │
│  │  - API calls                                           │  │
│  └───────────────────────────────────────────────────────┘  │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  Data Models (DTOs)                                    │  │
│  │  - External data structures                           │  │
│  │  - Serialization/deserialization                       │  │
│  └───────────────────────────────────────────────────────┘  │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  Data Sources                                         │  │
│  │  - Supabase client                                   │  │
│  │  - Local storage                                      │  │
│  │  - Remote APIs                                        │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 Proposed Directory Structure

```
lib/
├── main.dart
├── app.dart
│
├── config/
│   ├── supabase_config.dart
│   └── app_config.dart
│
├── core/
│   ├── design_system/
│   │   ├── theme/
│   │   │   ├── app_colors.dart
│   │   │   ├── app_text_styles.dart
│   │   │   ├── app_spacing.dart
│   │   │   ├── app_border_radius.dart
│   │   │   ├── app_elevation.dart
│   │   │   ├── app_theme_extensions.dart
│   │   │   ├── app_theme_data.dart
│   │   │   └── app_theme.dart
│   │   ├── constants/
│   │   │   ├── app_constants.dart
│   │   │   ├── app_strings.dart
│   │   │   └── app_assets.dart
│   │   └── widgets/
│   │       ├── app_button.dart
│   │       ├── app_card.dart
│   │       ├── app_input_field.dart
│   │       ├── app_loading_indicator.dart
│   │       ├── app_error_view.dart
│   │       └── app_empty_view.dart
│   │
│   ├── di/
│   │   ├── injection_container.dart
│   │   ├── core_injection.dart
│   │   └── feature_injection.dart
│   │
│   ├── errors/
│   │   ├── app_error.dart
│   │   ├── app_result.dart
│   │   └── error_handler.dart
│   │
│   ├── logging/
│   │   └── app_logger.dart
│   │
│   ├── network/
│   │   ├── network_info.dart
│   │   └── network_exceptions.dart
│   │
│   ├── notifications/
│   │   ├── notification_dispatcher.dart
│   │   └── notification_service.dart
│   │
│   ├── utils/
│   │   ├── date_utils.dart
│   │   ├── validation_utils.dart
│   │   └── extension_utils.dart
│   │
│   └── router/
│       ├── app_router.dart
│       ├── app_routes.dart
│       └── route_guards.dart
│
├── features/
│   │
│   ├── auth/
│   │   ├── domain/
│   │   │   ├── entities/
│   │   │   │   └── user.dart
│   │   │   ├── repositories/
│   │   │   │   └── auth_repository.dart
│   │   │   └── usecases/
│   │   │       ├── sign_in_usecase.dart
│   │   │       ├── sign_up_usecase.dart
│   │   │       ├── sign_out_usecase.dart
│   │   │       ├── check_session_usecase.dart
│   │   │       ├── forgot_password_usecase.dart
│   │   │       └── reset_password_usecase.dart
│   │   ├── data/
│   │   │   ├── models/
│   │   │   │   └── user_model.dart
│   │   │   ├── repositories/
│   │   │   │   └── auth_repository_impl.dart
│   │   │   └── datasources/
│   │   │       ├── auth_remote_datasource.dart
│   │   │       └── auth_local_datasource.dart
│   │   ├── presentation/
│   │   │   ├── bloc/
│   │   │   │   ├── auth_bloc.dart
│   │   │   │   ├── auth_event.dart
│   │   │   │   └── auth_state.dart
│   │   │   └── screens/
│   │   │       ├── login_screen.dart
│   │   │       ├── register_screen.dart
│   │   │       ├── pending_approval_screen.dart
│   │   │       ├── forgot_password_screen.dart
│   │   │       └── reset_password_screen.dart
│   │   └── auth_feature.dart
│   │
│   ├── orders/
│   │   ├── domain/
│   │   │   ├── entities/
│   │   │   │   ├── order.dart
│   │   │   │   ├── order_item.dart
│   │   │   │   └── order_template.dart
│   │   │   ├── value_objects/
│   │   │   │   ├── order_direction.dart
│   │   │   │   └── order_status.dart
│   │   │   ├── repositories/
│   │   │   │   └── order_repository.dart
│   │   │   └── usecases/
│   │   │       ├── get_orders_usecase.dart
│   │   │       ├── create_order_usecase.dart
│   │   │       ├── update_order_usecase.dart
│   │   │       ├── delete_order_usecase.dart
│   │   │       └── assign_order_usecase.dart
│   │   ├── data/
│   │   │   ├── models/
│   │   │   │   ├── order_model.dart
│   │   │   │   ├── order_item_model.dart
│   │   │   │   └── order_template_model.dart
│   │   │   ├── repositories/
│   │   │   │   └── order_repository_impl.dart
│   │   │   └── datasources/
│   │   │       ├── order_remote_datasource.dart
│   │   │       └── order_local_datasource.dart
│   │   ├── presentation/
│   │   │   ├── bloc/
│   │   │   │   ├── orders_bloc.dart
│   │   │   │   ├── orders_event.dart
│   │   │   │   └── orders_state.dart
│   │   │   ├── screens/
│   │   │   │   ├── orders_list_screen.dart
│   │   │   │   ├── create_order_screen.dart
│   │   │   │   ├── edit_order_screen.dart
│   │   │   │   └── order_detail_screen.dart
│   │   │   └── widgets/
│   │   │       ├── order_card.dart
│   │   │       ├── order_status_badge.dart
│   │   │       └── order_list_tile.dart
│   │   └── orders_feature.dart
│   │
│   ├── inventory/
│   │   ├── domain/
│   │   │   ├── entities/
│   │   │   │   └── inventory_item.dart
│   │   │   ├── repositories/
│   │   │   │   └── inventory_repository.dart
│   │   │   └── usecases/
│   │   │       ├── get_inventory_items_usecase.dart
│   │   │       ├── create_inventory_item_usecase.dart
│   │   │       ├── update_inventory_item_usecase.dart
│   │   │       └── delete_inventory_item_usecase.dart
│   │   ├── data/
│   │   │   ├── models/
│   │   │   │   └── inventory_item_model.dart
│   │   │   ├── repositories/
│   │   │   │   └── inventory_repository_impl.dart
│   │   │   └── datasources/
│   │   │       ├── inventory_remote_datasource.dart
│   │   │       └── inventory_local_datasource.dart
│   │   ├── presentation/
│   │   │   ├── bloc/
│   │   │   │   ├── inventory_bloc.dart
│   │   │   │   ├── inventory_event.dart
│   │   │   │   └── inventory_state.dart
│   │   │   ├── screens/
│   │   │   │   ├── inventory_management_screen.dart
│   │   │   │   ├── inventory_form_screen.dart
│   │   │   │   ├── inventory_item_detail_screen.dart
│   │   │   │   └── inventory_bulk_edit_screen.dart
│   │   │   └── widgets/
│   │   │       ├── inventory_item_card.dart
│   │   │       ├── availability_badge.dart
│   │   │       └── inventory_search_bar.dart
│   │   └── inventory_feature.dart
│   │
│   ├── entities/
│   │   ├── domain/
│   │   │   ├── entities/
│   │   │   │   └── entity.dart
│   │   │   ├── repositories/
│   │   │   │   └── entity_repository.dart
│   │   │   └── usecases/
│   │   │       ├── get_entities_usecase.dart
│   │   │       ├── create_entity_usecase.dart
│   │   │       ├── update_entity_usecase.dart
│   │   │       └── delete_entity_usecase.dart
│   │   ├── data/
│   │   │   ├── models/
│   │   │   │   └── entity_model.dart
│   │   │   ├── repositories/
│   │   │   │   └── entity_repository_impl.dart
│   │   │   └── datasources/
│   │   │       └── entity_remote_datasource.dart
│   │   ├── presentation/
│   │   │   ├── bloc/
│   │   │   │   ├── entities_bloc.dart
│   │   │   │   ├── entities_event.dart
│   │   │   │   └── entities_state.dart
│   │   │   ├── screens/
│   │   │   │   └── entities_screen.dart
│   │   │   └── widgets/
│   │   │       └── entity_form_sheet.dart
│   │   └── entities_feature.dart
│   │
│   ├── chat/
│   │   ├── domain/
│   │   │   ├── entities/
│   │   │   │   ├── chat_thread.dart
│   │   │   │   ├── chat_message.dart
│   │   │   │   └── chat_participant.dart
│   │   │   ├── repositories/
│   │   │   │   └── chat_repository.dart
│   │   │   └── usecases/
│   │   │       ├── get_chat_threads_usecase.dart
│   │   │       ├── get_chat_messages_usecase.dart
│   │   │       ├── send_message_usecase.dart
│   │   │       ├── create_thread_usecase.dart
│   │   │       └── mark_as_read_usecase.dart
│   │   ├── data/
│   │   │   ├── models/
│   │   │   │   ├── chat_thread_model.dart
│   │   │   │   ├── chat_message_model.dart
│   │   │   │   └── chat_participant_model.dart
│   │   │   ├── repositories/
│   │   │   │   └── chat_repository_impl.dart
│   │   │   └── datasources/
│   │   │       ├── chat_remote_datasource.dart
│   │   │       └── chat_local_datasource.dart
│   │   ├── presentation/
│   │   │   ├── bloc/
│   │   │   │   ├── chat_threads_bloc.dart
│   │   │   │   ├── chat_messages_bloc.dart
│   │   │   │   ├── chat_event.dart
│   │   │   │   └── chat_state.dart
│   │   │   ├── screens/
│   │   │   │   ├── chat_hub_screen.dart
│   │   │   │   ├── chat_thread_screen.dart
│   │   │   │   ├── create_thread_screen.dart
│   │   │   │   └── chat_picker_screen.dart
│   │   │   └── widgets/
│   │   │       ├── chat_message_bubble.dart
│   │   │       ├── chat_thread_card.dart
│   │   │       ├── mention_suggestions.dart
│   │   │       └── chat_input_field.dart
│   │   └── chat_feature.dart
│   │
│   ├── notifications/
│   │   ├── domain/
│   │   │   ├── entities/
│   │   │   │   └── app_notification.dart
│   │   │   ├── repositories/
│   │   │   │   └── notifications_repository.dart
│   │   │   └── usecases/
│   │   │       ├── get_notifications_usecase.dart
│   │   │       ├── mark_as_read_usecase.dart
│   │   │       └── clear_notifications_usecase.dart
│   │   ├── data/
│   │   │   ├── models/
│   │   │   │   └── app_notification_model.dart
│   │   │   ├── repositories/
│   │   │   │   └── notifications_repository_impl.dart
│   │   │   └── datasources/
│   │   │       └── notifications_remote_datasource.dart
│   │   ├── presentation/
│   │   │   ├── bloc/
│   │   │   │   ├── notifications_bloc.dart
│   │   │   │   ├── notifications_event.dart
│   │   │   │   └── notifications_state.dart
│   │   │   ├── screens/
│   │   │   │   └── notifications_screen.dart
│   │   │   └── widgets/
│   │   │       ├── notification_card.dart
│   │   │       └── notification_badge.dart
│   │   └── notifications_feature.dart
│   │
│   ├── profile/
│   │   ├── domain/
│   │   │   ├── entities/
│   │   │   │   └── profile.dart
│   │   │   ├── repositories/
│   │   │   │   └── profile_repository.dart
│   │   │   └── usecases/
│   │   │       ├── get_profile_usecase.dart
│   │   │       ├── update_profile_usecase.dart
│   │   │       └── upload_avatar_usecase.dart
│   │   ├── data/
│   │   │   ├── models/
│   │   │   │   └── profile_model.dart
│   │   │   ├── repositories/
│   │   │   │   └── profile_repository_impl.dart
│   │   │   └── datasources/
│   │   │       └── profile_remote_datasource.dart
│   │   ├── presentation/
│   │   │   ├── bloc/
│   │   │   │   ├── profile_bloc.dart
│   │   │   │   ├── profile_event.dart
│   │   │   │   └── profile_state.dart
│   │   │   └── screens/
│   │   │       └── profile_screen.dart
│   │   └── profile_feature.dart
│   │
│   ├── manager/
│   │   ├── domain/
│   │   │   ├── entities/
│   │   │   │   ├── manager_stats.dart
│   │   │   │   ├── user_order.dart
│   │   │   │   └── task_detail.dart
│   │   │   ├── repositories/
│   │   │   │   └── manager_repository.dart
│   │   │   └── usecases/
│   │   │       ├── get_manager_stats_usecase.dart
│   │   │       ├── get_pending_users_usecase.dart
│   │   │       ├── approve_user_usecase.dart
│   │   │       ├── get_user_orders_usecase.dart
│   │   │       └── get_task_details_usecase.dart
│   │   ├── data/
│   │   │   ├── models/
│   │   │   │   ├── manager_stats_model.dart
│   │   │   │   ├── user_order_model.dart
│   │   │   │   └── task_detail_model.dart
│   │   │   ├── repositories/
│   │   │   │   └── manager_repository_impl.dart
│   │   │   └── datasources/
│   │   │       └── manager_remote_datasource.dart
│   │   ├── presentation/
│   │   │   ├── bloc/
│   │   │   │   ├── manager_bloc.dart
│   │   │   │   ├── manager_event.dart
│   │   │   │   └── manager_state.dart
│   │   │   ├── screens/
│   │   │   │   ├── manager_home_screen.dart
│   │   │   │   ├── manager_pending_users_screen.dart
│   │   │   │   ├── monitor_tasks_screen.dart
│   │   │   │   ├── monitor_users_screen.dart
│   │   │   │   ├── rep_list_screen.dart
│   │   │   │   ├── stats_screen.dart
│   │   │   │   ├── task_detail_screen.dart
│   │   │   │   ├── user_orders_screen.dart
│   │   │   │   └── user_type_users_screen.dart
│   │   │   └── widgets/
│   │   │       ├── stats_card.dart
│   │   │       ├── user_list_item.dart
│   │   │       └── task_card.dart
│   │   └── manager_feature.dart
│   │
│   ├── rep/
│   │   ├── domain/
│   │   │   ├── entities/
│   │   │   │   └── rep_order.dart
│   │   │   ├── repositories/
│   │   │   │   └── rep_orders_repository.dart
│   │   │   └── usecases/
│   │   │       ├── get_rep_orders_usecase.dart
│   │   │       ├── get_rep_order_detail_usecase.dart
│   │   │       ├── update_order_status_usecase.dart
│   │   │       └── pick_up_order_usecase.dart
│   │   ├── data/
│   │   │   ├── models/
│   │   │   │   └── rep_order_model.dart
│   │   │   ├── repositories/
│   │   │   │   └── rep_orders_repository_impl.dart
│   │   │   └── datasources/
│   │   │       └── rep_orders_remote_datasource.dart
│   │   ├── presentation/
│   │   │   ├── bloc/
│   │   │   │   ├── rep_orders_bloc.dart
│   │   │   │   ├── rep_orders_event.dart
│   │   │   │   └── rep_orders_state.dart
│   │   │   ├── screens/
│   │   │   │   ├── rep_home_screen.dart
│   │   │   │   └── rep_order_detail_screen.dart
│   │   │   └── widgets/
│   │   │       ├── rep_order_card.dart
│   │   │       └── status_action_button.dart
│   │   └── rep_feature.dart
│   │
│   ├── storage/
│   │   ├── domain/
│   │   │   ├── entities/
│   │   │   │   └── storage_order.dart
│   │   │   ├── repositories/
│   │   │   │   └── storage_repository.dart
│   │   │   └── usecases/
│   │   │       ├── get_storage_orders_usecase.dart
│   │   │       ├── get_storage_order_detail_usecase.dart
│   │   │       ├── receive_order_usecase.dart
│   │   │       └── deliver_order_usecase.dart
│   │   ├── data/
│   │   │   ├── models/
│   │   │   │   └── storage_order_model.dart
│   │   │   ├── repositories/
│   │   │   │   └── storage_repository_impl.dart
│   │   │   └── datasources/
│   │   │       └── storage_remote_datasource.dart
│   │   ├── presentation/
│   │   │   ├── bloc/
│   │   │   │   ├── storage_bloc.dart
│   │   │   │   ├── storage_event.dart
│   │   │   │   └── storage_state.dart
│   │   │   ├── screens/
│   │   │   │   ├── storage_home_screen.dart
│   │   │   │   └── storage_order_detail_screen.dart
│   │   │   └── widgets/
│   │   │       ├── storage_order_card.dart
│   │   │       └── storage_action_button.dart
│   │   └── storage_feature.dart
│   │
│   └── shared/
│       ├── domain/
│       │   ├── entities/
│       │   │   ├── audit_log_entry.dart
│       │   │   ├── inventory_audit_log_entry.dart
│       │   │   ├── order_edit_log_entry.dart
│       │   │   └── draft_order_item.dart
│       │   └── value_objects/
│       │       └── order_status_theme.dart
│       └── presentation/
│           └── widgets/
│               ├── order_list_tile.dart
│               └── receipt_viewer_screen.dart
│
└── shared/
    └── permissions/
        └── permission_utils.dart
```

### 2.3 Key Architectural Decisions

#### 2.3.1 Feature-Based Organization
- Each feature is self-contained with domain, data, and presentation layers
- Features export a barrel file (`*_feature.dart`) for clean imports
- Features are independent and can be developed/tested in isolation

#### 2.3.2 Clean Architecture Layers
**Domain Layer (Core Business Logic)**
- Contains entities (business models)
- Defines repository interfaces
- Implements use cases (business logic)
- No dependencies on other layers
- Pure Dart code, no Flutter dependencies

**Data Layer (Data Access)**
- Implements repository interfaces
- Contains data models (DTOs)
- Manages data sources (Supabase, local storage)
- Depends on domain layer
- Converts between data models and domain entities

**Presentation Layer (UI)**
- Contains screens and widgets
- Implements state management (BLoC)
- Depends on domain layer through use cases
- No direct access to data layer

#### 2.3.3 Dependency Flow
```
Presentation → Domain ← Data
```
- Dependencies point inward toward the domain
- Domain layer has no dependencies
- Data layer implements domain interfaces
- Presentation layer uses domain use cases

#### 2.3.4 State Management
- Continue using BLoC (Cubit) for state management
- Each feature has its own BLoC
- BLoCs are injected through GetIt
- State is held in presentation layer

#### 2.3.5 Design System Location
- Centralized in `lib/core/design_system/`
- Contains all theming, constants, and reusable widgets
- Accessible to all features
- No feature-specific design system code

---

## 3. Design System Architecture

### 3.1 Design System Overview

The design system provides a centralized, consistent approach to UI styling and components. It follows Material Design 3 principles while being tailored to URA CORE's specific needs.

### 3.2 Color System Architecture

#### 3.2.1 Color Organization

```dart
// lib/core/design_system/theme/app_colors.dart

class AppColors {
  const AppColors._();

  // ========================================
  // Brand Colors
  // ========================================
  static const Color primary = Color(0xFF00897B); // Teal
  static const Color primaryDark = Color(0xFF00695C);
  static const Color primaryLight = Color(0xFF4DB6AC);
  static const Color accent = Color(0xFF26A69A);
  static const Color accentDark = Color(0xFF00796B);

  // ========================================
  // Semantic Colors (Status)
  // ========================================
  static const Color success = Color(0xFF4CAF50);
  static const Color successLight = Color(0xFF81C784);
  static const Color successDark = Color(0xFF388E3C);

  static const Color error = Color(0xFFE53935);
  static const Color errorLight = Color(0xFFEF5350);
  static const Color errorDark = Color(0xFFD32F2F);

  static const Color warning = Color(0xFFFFB300);
  static const Color warningLight = Color(0xFFFFCA28);
  static const Color warningDark = Color(0xFFFFA000);

  static const Color info = Color(0xFF2196F3);
  static const Color infoLight = Color(0xFF64B5F6);
  static const Color infoDark = Color(0xFF1976D2);

  // ========================================
  // Order Status Colors (Traffic Light)
  // ========================================
  static const Color orderStatusAssigned = Color(0xFFE53935); // Red
  static const Color orderStatusPickedUp = Color(0xFFE53935); // Red
  static const Color orderStatusOnTheMove = Color(0xFFFF8F00); // Amber
  static const Color orderStatusDelivered = Color(0xFF4CAF50); // Green
  static const Color orderStatusDeliveredToStorage = Color(0xFF4CAF50); // Green

  // ========================================
  // Order Direction Colors
  // ========================================
  static const Color orderDirectionOutbound = Color(0xFFFF9800); // Orange
  static const Color orderDirectionInboundRep = Color(0xFF009688); // Teal
  static const Color orderDirectionInboundExternal = Color(0xFF3F51B5); // Indigo

  // ========================================
  // Neutral Colors
  // ========================================
  static const Color white = Color(0xFFFFFFFF);
  static const Color black = Color(0xFF000000);

  static const Color grey50 = Color(0xFFFAFAFA);
  static const Color grey100 = Color(0xFFF5F5F5);
  static const Color grey200 = Color(0xFFEEEEEE);
  static const Color grey300 = Color(0xFFE0E0E0);
  static const Color grey400 = Color(0xFFBDBDBD);
  static const Color grey500 = Color(0xFF9E9E9E);
  static const Color grey600 = Color(0xFF757575);
  static const Color grey700 = Color(0xFF616161);
  static const Color grey800 = Color(0xFF424242);
  static const Color grey900 = Color(0xFF212121);

  // ========================================
  // Surface Colors
  // ========================================
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFF5F5F5);
  static const Color surfaceContainer = Color(0xFFFAFAFA);
  static const Color surfaceContainerLow = Color(0xFFFAFAFA);
  static const Color surfaceContainerHigh = Color(0xFFEEEEEE);

  // ========================================
  // Background Colors
  // ========================================
  static const Color background = Color(0xFFFAFAFA);
  static const Color backgroundVariant = Color(0xFFF5F5F5);

  // ========================================
  // Text Colors
  // ========================================
  static const Color textPrimary = Color(0xFF212121);
  static const Color textSecondary = Color(0xFF616161);
  static const Color textTertiary = Color(0xFF9E9E9E);
  static const Color textDisabled = Color(0xFFBDBDBD);
  static const Color textOnPrimary = Color(0xFFFFFFFF);
  static const Color textOnError = Color(0xFFFFFFFF);
  static const Color textOnSuccess = Color(0xFFFFFFFF);
  static const Color textOnWarning = Color(0xFF212121);
  static const Color textOnInfo = Color(0xFFFFFFFF);

  // ========================================
  // Border Colors
  // ========================================
  static const Color border = Color(0xFFE0E0E0);
  static const Color borderLight = Color(0xFFEEEEEE);
  static const Color borderDark = Color(0xFFBDBDBD);
  static const Color borderFocus = Color(0xFF00897B);
  static const Color borderError = Color(0xFFE53935);

  // ========================================
  // Icon Colors
  // ========================================
  static const Color iconPrimary = Color(0xFF212121);
  static const Color iconSecondary = Color(0xFF616161);
  static const Color iconDisabled = Color(0xFFBDBDBD);
  static const Color iconOnPrimary = Color(0xFFFFFFFF);

  // ========================================
  // Overlay Colors
  // ========================================
  static const Color overlay = Color(0x80000000);
  static const Color overlayLight = Color(0x40000000);
}
```

#### 3.2.2 Theme Extensions

```dart
// lib/core/design_system/theme/app_theme_extensions.dart

@immutable
class AppThemeColors extends ThemeExtension<AppThemeColors> {
  // Backgrounds
  final Color background;
  final Color surface;
  final Color surfaceVariant;
  final Color surfaceContainer;

  // Text
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textDisabled;

  // Primary
  final Color primary;
  final Color onPrimary;
  final Color primaryContainer;
  final Color onPrimaryContainer;

  // Secondary
  final Color secondary;
  final Color onSecondary;
  final Color secondaryContainer;
  final Color onSecondaryContainer;

  // Status
  final Color success;
  final Color onSuccess;
  final Color error;
  final Color onError;
  final Color warning;
  final Color onWarning;
  final Color info;
  final Color onInfo;

  // Borders
  final Color border;
  final Color borderFocus;
  final Color borderError;

  // Icons
  final Color iconPrimary;
  final Color iconSecondary;
  final Color iconDisabled;

  const AppThemeColors({
    required this.background,
    required this.surface,
    required this.surfaceVariant,
    required this.surfaceContainer,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textDisabled,
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.secondary,
    required this.onSecondary,
    required this.secondaryContainer,
    required this.onSecondaryContainer,
    required this.success,
    required this.onSuccess,
    required this.error,
    required this.onError,
    required this.warning,
    required this.onWarning,
    required this.info,
    required this.onInfo,
    required this.border,
    required this.borderFocus,
    required this.borderError,
    required this.iconPrimary,
    required this.iconSecondary,
    required this.iconDisabled,
  });

  @override
  AppThemeColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceVariant,
    Color? surfaceContainer,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? textDisabled,
    Color? primary,
    Color? onPrimary,
    Color? primaryContainer,
    Color? onPrimaryContainer,
    Color? secondary,
    Color? onSecondary,
    Color? secondaryContainer,
    Color? onSecondaryContainer,
    Color? success,
    Color? onSuccess,
    Color? error,
    Color? onError,
    Color? warning,
    Color? onWarning,
    Color? info,
    Color? onInfo,
    Color? border,
    Color? borderFocus,
    Color? borderError,
    Color? iconPrimary,
    Color? iconSecondary,
    Color? iconDisabled,
  }) {
    return AppThemeColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceVariant: surfaceVariant ?? this.surfaceVariant,
      surfaceContainer: surfaceContainer ?? this.surfaceContainer,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      textDisabled: textDisabled ?? this.textDisabled,
      primary: primary ?? this.primary,
      onPrimary: onPrimary ?? this.onPrimary,
      primaryContainer: primaryContainer ?? this.primaryContainer,
      onPrimaryContainer: onPrimaryContainer ?? this.onPrimaryContainer,
      secondary: secondary ?? this.secondary,
      onSecondary: onSecondary ?? this.onSecondary,
      secondaryContainer: secondaryContainer ?? this.secondaryContainer,
      onSecondaryContainer: onSecondaryContainer ?? this.onSecondaryContainer,
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      error: error ?? this.error,
      onError: onError ?? this.onError,
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
      info: info ?? this.info,
      onInfo: onInfo ?? this.onInfo,
      border: border ?? this.border,
      borderFocus: borderFocus ?? this.borderFocus,
      borderError: borderError ?? this.borderError,
      iconPrimary: iconPrimary ?? this.iconPrimary,
      iconSecondary: iconSecondary ?? this.iconSecondary,
      iconDisabled: iconDisabled ?? this.iconDisabled,
    );
  }

  @override
  AppThemeColors lerp(ThemeExtension<AppThemeColors>? other, double t) {
    if (other is! AppThemeColors) return this;
    return AppThemeColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceVariant: Color.lerp(surfaceVariant, other.surfaceVariant, t)!,
      surfaceContainer: Color.lerp(surfaceContainer, other.surfaceContainer, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      textDisabled: Color.lerp(textDisabled, other.textDisabled, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      onPrimary: Color.lerp(onPrimary, other.onPrimary, t)!,
      primaryContainer: Color.lerp(primaryContainer, other.primaryContainer, t)!,
      onPrimaryContainer: Color.lerp(onPrimaryContainer, other.onPrimaryContainer, t)!,
      secondary: Color.lerp(secondary, other.secondary, t)!,
      onSecondary: Color.lerp(onSecondary, other.onSecondary, t)!,
      secondaryContainer: Color.lerp(secondaryContainer, other.secondaryContainer, t)!,
      onSecondaryContainer: Color.lerp(onSecondaryContainer, other.onSecondaryContainer, t)!,
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      error: Color.lerp(error, other.error, t)!,
      onError: Color.lerp(onError, other.onError, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      info: Color.lerp(info, other.info, t)!,
      onInfo: Color.lerp(onInfo, other.onInfo, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderFocus: Color.lerp(borderFocus, other.borderFocus, t)!,
      borderError: Color.lerp(borderError, other.borderError, t)!,
      iconPrimary: Color.lerp(iconPrimary, other.iconPrimary, t)!,
      iconSecondary: Color.lerp(iconSecondary, other.iconSecondary, t)!,
      iconDisabled: Color.lerp(iconDisabled, other.iconDisabled, t)!,
    );
  }

  static const light = AppThemeColors(
    background: AppColors.background,
    surface: AppColors.surface,
    surfaceVariant: AppColors.surfaceVariant,
    surfaceContainer: AppColors.surfaceContainer,
    textPrimary: AppColors.textPrimary,
    textSecondary: AppColors.textSecondary,
    textTertiary: AppColors.textTertiary,
    textDisabled: AppColors.textDisabled,
    primary: AppColors.primary,
    onPrimary: AppColors.textOnPrimary,
    primaryContainer: AppColors.primaryLight,
    onPrimaryContainer: AppColors.primaryDark,
    secondary: AppColors.accent,
    onSecondary: AppColors.white,
    secondaryContainer: AppColors.accentDark,
    onSecondaryContainer: AppColors.white,
    success: AppColors.success,
    onSuccess: AppColors.textOnSuccess,
    error: AppColors.error,
    onError: AppColors.textOnError,
    warning: AppColors.warning,
    onWarning: AppColors.textOnWarning,
    info: AppColors.info,
    onInfo: AppColors.textOnInfo,
    border: AppColors.border,
    borderFocus: AppColors.borderFocus,
    borderError: AppColors.borderError,
    iconPrimary: AppColors.iconPrimary,
    iconSecondary: AppColors.iconSecondary,
    iconDisabled: AppColors.iconDisabled,
  );

  static const dark = AppThemeColors(
    background: AppColors.grey900,
    surface: AppColors.grey800,
    surfaceVariant: AppColors.grey700,
    surfaceContainer: AppColors.grey800,
    textPrimary: AppColors.white,
    textSecondary: AppColors.grey300,
    textTertiary: AppColors.grey500,
    textDisabled: AppColors.grey600,
    primary: AppColors.primaryLight,
    onPrimary: AppColors.white,
    primaryContainer: AppColors.primaryDark,
    onPrimaryContainer: AppColors.white,
    secondary: AppColors.accent,
    onSecondary: AppColors.white,
    secondaryContainer: AppColors.accentDark,
    onSecondaryContainer: AppColors.white,
    success: AppColors.successLight,
    onSuccess: AppColors.white,
    error: AppColors.errorLight,
    onError: AppColors.white,
    warning: AppColors.warningLight,
    onWarning: AppColors.black,
    info: AppColors.infoLight,
    onInfo: AppColors.white,
    border: AppColors.grey700,
    borderFocus: AppColors.primaryLight,
    borderError: AppColors.errorLight,
    iconPrimary: AppColors.white,
    iconSecondary: AppColors.grey300,
    iconDisabled: AppColors.grey600,
  );
}

@immutable
class AppThemeTextStyles extends ThemeExtension<AppThemeTextStyles> {
  final TextStyle displayLarge;
  final TextStyle displayMedium;
  final TextStyle displaySmall;
  final TextStyle headlineLarge;
  final TextStyle headlineMedium;
  final TextStyle headlineSmall;
  final TextStyle titleLarge;
  final TextStyle titleMedium;
  final TextStyle titleSmall;
  final TextStyle bodyLarge;
  final TextStyle bodyMedium;
  final TextStyle bodySmall;
  final TextStyle labelLarge;
  final TextStyle labelMedium;
  final TextStyle labelSmall;

  const AppThemeTextStyles({
    required this.displayLarge,
    required this.displayMedium,
    required this.displaySmall,
    required this.headlineLarge,
    required this.headlineMedium,
    required this.headlineSmall,
    required this.titleLarge,
    required this.titleMedium,
    required this.titleSmall,
    required this.bodyLarge,
    required this.bodyMedium,
    required this.bodySmall,
    required this.labelLarge,
    required this.labelMedium,
    required this.labelSmall,
  });

  @override
  AppThemeTextStyles copyWith({
    TextStyle? displayLarge,
    TextStyle? displayMedium,
    TextStyle? displaySmall,
    TextStyle? headlineLarge,
    TextStyle? headlineMedium,
    TextStyle? headlineSmall,
    TextStyle? titleLarge,
    TextStyle? titleMedium,
    TextStyle? titleSmall,
    TextStyle? bodyLarge,
    TextStyle? bodyMedium,
    TextStyle? bodySmall,
    TextStyle? labelLarge,
    TextStyle? labelMedium,
    TextStyle? labelSmall,
  }) {
    return AppThemeTextStyles(
      displayLarge: displayLarge ?? this.displayLarge,
      displayMedium: displayMedium ?? this.displayMedium,
      displaySmall: displaySmall ?? this.displaySmall,
      headlineLarge: headlineLarge ?? this.headlineLarge,
      headlineMedium: headlineMedium ?? this.headlineMedium,
      headlineSmall: headlineSmall ?? this.headlineSmall,
      titleLarge: titleLarge ?? this.titleLarge,
      titleMedium: titleMedium ?? this.titleMedium,
      titleSmall: titleSmall ?? this.titleSmall,
      bodyLarge: bodyLarge ?? this.bodyLarge,
      bodyMedium: bodyMedium ?? this.bodyMedium,
      bodySmall: bodySmall ?? this.bodySmall,
      labelLarge: labelLarge ?? this.labelLarge,
      labelMedium: labelMedium ?? this.labelMedium,
      labelSmall: labelSmall ?? this.labelSmall,
    );
  }

  @override
  AppThemeTextStyles lerp(ThemeExtension<AppThemeTextStyles>? other, double t) {
    if (other is! AppThemeTextStyles) return this;
    return AppThemeTextStyles(
      displayLarge: TextStyle.lerp(displayLarge, other.displayLarge, t)!,
      displayMedium: TextStyle.lerp(displayMedium, other.displayMedium, t)!,
      displaySmall: TextStyle.lerp(displaySmall, other.displaySmall, t)!,
      headlineLarge: TextStyle.lerp(headlineLarge, other.headlineLarge, t)!,
      headlineMedium: TextStyle.lerp(headlineMedium, other.headlineMedium, t)!,
      headlineSmall: TextStyle.lerp(headlineSmall, other.headlineSmall, t)!,
      titleLarge: TextStyle.lerp(titleLarge, other.titleLarge, t)!,
      titleMedium: TextStyle.lerp(titleMedium, other.titleMedium, t)!,
      titleSmall: TextStyle.lerp(titleSmall, other.titleSmall, t)!,
      bodyLarge: TextStyle.lerp(bodyLarge, other.bodyLarge, t)!,
      bodyMedium: TextStyle.lerp(bodyMedium, other.bodyMedium, t)!,
      bodySmall: TextStyle.lerp(bodySmall, other.bodySmall, t)!,
      labelLarge: TextStyle.lerp(labelLarge, other.labelLarge, t)!,
      labelMedium: TextStyle.lerp(labelMedium, other.labelMedium, t)!,
      labelSmall: TextStyle.lerp(labelSmall, other.labelSmall, t)!,
    );
  }

  static AppThemeTextStyles light(BuildContext context) {
    return AppThemeTextStyles(
      displayLarge: GoogleFonts.tajawal(
        fontSize: 57,
        fontWeight: FontWeight.w400,
        letterSpacing: -0.25,
      ),
      displayMedium: GoogleFonts.tajawal(
        fontSize: 45,
        fontWeight: FontWeight.w400,
      ),
      displaySmall: GoogleFonts.tajawal(
        fontSize: 36,
        fontWeight: FontWeight.w400,
      ),
      headlineLarge: GoogleFonts.tajawal(
        fontSize: 32,
        fontWeight: FontWeight.w600,
      ),
      headlineMedium: GoogleFonts.tajawal(
        fontSize: 28,
        fontWeight: FontWeight.w600,
      ),
      headlineSmall: GoogleFonts.tajawal(
        fontSize: 24,
        fontWeight: FontWeight.w600,
      ),
      titleLarge: GoogleFonts.tajawal(
        fontSize: 22,
        fontWeight: FontWeight.w500,
      ),
      titleMedium: GoogleFonts.tajawal(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.15,
      ),
      titleSmall: GoogleFonts.tajawal(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.1,
      ),
      bodyLarge: GoogleFonts.tajawal(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.5,
      ),
      bodyMedium: GoogleFonts.tajawal(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.25,
      ),
      bodySmall: GoogleFonts.tajawal(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.4,
      ),
      labelLarge: GoogleFonts.tajawal(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.1,
      ),
      labelMedium: GoogleFonts.tajawal(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
      ),
      labelSmall: GoogleFonts.tajawal(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
      ),
    );
  }

  static AppThemeTextStyles dark(BuildContext context) {
    return AppThemeTextStyles(
      displayLarge: GoogleFonts.tajawal(
        fontSize: 57,
        fontWeight: FontWeight.w400,
        letterSpacing: -0.25,
      ),
      displayMedium: GoogleFonts.tajawal(
        fontSize: 45,
        fontWeight: FontWeight.w400,
      ),
      displaySmall: GoogleFonts.tajawal(
        fontSize: 36,
        fontWeight: FontWeight.w400,
      ),
      headlineLarge: GoogleFonts.tajawal(
        fontSize: 32,
        fontWeight: FontWeight.w600,
      ),
      headlineMedium: GoogleFonts.tajawal(
        fontSize: 28,
        fontWeight: FontWeight.w600,
      ),
      headlineSmall: GoogleFonts.tajawal(
        fontSize: 24,
        fontWeight: FontWeight.w600,
      ),
      titleLarge: GoogleFonts.tajawal(
        fontSize: 22,
        fontWeight: FontWeight.w500,
      ),
      titleMedium: GoogleFonts.tajawal(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.15,
      ),
      titleSmall: GoogleFonts.tajawal(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.1,
      ),
      bodyLarge: GoogleFonts.tajawal(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.5,
      ),
      bodyMedium: GoogleFonts.tajawal(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.25,
      ),
      bodySmall: GoogleFonts.tajawal(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.4,
      ),
      labelLarge: GoogleFonts.tajawal(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.1,
      ),
      labelMedium: GoogleFonts.tajawal(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
      ),
      labelSmall: GoogleFonts.tajawal(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
      ),
    );
  }
}
```

### 3.3 Typography System Architecture

```dart
// lib/core/design_system/theme/app_text_styles.dart

class AppTextStyles {
  const AppTextStyles._();

  // ========================================
  // Display Styles (for hero sections)
  // ========================================
  static const TextStyle displayLarge = TextStyle(
    fontSize: 57,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.25,
    height: 1.15,
  );

  static const TextStyle displayMedium = TextStyle(
    fontSize: 45,
    fontWeight: FontWeight.w400,
    height: 1.2,
  );

  static const TextStyle displaySmall = TextStyle(
    fontSize: 36,
    fontWeight: FontWeight.w400,
    height: 1.25,
  );

  // ========================================
  // Headline Styles (for page titles)
  // ========================================
  static const TextStyle headlineLarge = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  static const TextStyle headlineMedium = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w600,
    height: 1.35,
  );

  static const TextStyle headlineSmall = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w600,
    height: 1.4,
  );

  // ========================================
  // Title Styles (for card titles, section headers)
  // ========================================
  static const TextStyle titleLarge = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w500,
    height: 1.4,
    letterSpacing: 0,
  );

  static const TextStyle titleMedium = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 1.5,
    letterSpacing: 0.15,
  );

  static const TextStyle titleSmall = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.5,
    letterSpacing: 0.1,
  );

  // ========================================
  // Body Styles (for main content)
  // ========================================
  static const TextStyle bodyLarge = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.5,
    letterSpacing: 0.5,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.5,
    letterSpacing: 0.25,
  );

  static const TextStyle bodySmall = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.5,
    letterSpacing: 0.4,
  );

  // ========================================
  // Label Styles (for buttons, tags, badges)
  // ========================================
  static const TextStyle labelLarge = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 1.5,
    letterSpacing: 0.1,
  );

  static const TextStyle labelMedium = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.5,
    letterSpacing: 0.5,
  );

  static const TextStyle labelSmall = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    height: 1.5,
    letterSpacing: 0.5,
  );

  // ========================================
  // Helper Methods
  // ========================================
  static TextStyle withColor(TextStyle style, Color color) {
    return style.copyWith(color: color);
  }

  static TextStyle withWeight(TextStyle style, FontWeight weight) {
    return style.copyWith(fontWeight: weight);
  }

  static TextStyle withHeight(TextStyle style, double height) {
    return style.copyWith(height: height);
  }
}
```

### 3.4 Spacing/Sizing System Architecture

```dart
// lib/core/design_system/theme/app_spacing.dart

class AppSpacing {
  const AppSpacing._();

  // ========================================
  // Screen Padding
  // ========================================
  static const double screenHorizontal = 24.0;
  static const double screenVertical = 24.0;
  static const double screenPadding = 24.0;

  // ========================================
  // Horizontal Spacing
  // ========================================
  static const double horizontalXSmall = 4.0;
  static const double horizontalSmall = 8.0;
  static const double horizontalMedium = 12.0;
  static const double horizontalLarge = 16.0;
  static const double horizontalXLarge = 20.0;
  static const double horizontalXXLarge = 24.0;
  static const double horizontalXXXLarge = 32.0;

  // ========================================
  // Vertical Spacing
  // ========================================
  static const double verticalXSmall = 4.0;
  static const double verticalSmall = 8.0;
  static const double verticalMedium = 12.0;
  static const double verticalLarge = 16.0;
  static const double verticalXLarge = 20.0;
  static const double verticalXXLarge = 24.0;
  static const double verticalXXXLarge = 32.0;

  // ========================================
  // Edge Insets Helpers
  // ========================================
  static const EdgeInsets allXSmall = EdgeInsets.all(horizontalXSmall);
  static const EdgeInsets allSmall = EdgeInsets.all(horizontalSmall);
  static const EdgeInsets allMedium = EdgeInsets.all(horizontalMedium);
  static const EdgeInsets allLarge = EdgeInsets.all(horizontalLarge);
  static const EdgeInsets allXLarge = EdgeInsets.all(horizontalXLarge);
  static const EdgeInsets allXXLarge = EdgeInsets.all(horizontalXXLarge);
  static const EdgeInsets allXXXLarge = EdgeInsets.all(horizontalXXXLarge);

  static const EdgeInsets horizontalXSmallPadding =
      EdgeInsets.symmetric(horizontal: horizontalXSmall);
  static const EdgeInsets horizontalSmallPadding =
      EdgeInsets.symmetric(horizontal: horizontalSmall);
  static const EdgeInsets horizontalMediumPadding =
      EdgeInsets.symmetric(horizontal: horizontalMedium);
  static const EdgeInsets horizontalLargePadding =
      EdgeInsets.symmetric(horizontal: horizontalLarge);
  static const EdgeInsets horizontalXLargePadding =
      EdgeInsets.symmetric(horizontal: horizontalXLarge);
  static const EdgeInsets horizontalXXLargePadding =
      EdgeInsets.symmetric(horizontal: horizontalXXLarge);
  static const EdgeInsets horizontalXXXLargePadding =
      EdgeInsets.symmetric(horizontal: horizontalXXXLarge);

  static const EdgeInsets verticalXSmallPadding =
      EdgeInsets.symmetric(vertical: verticalXSmall);
  static const EdgeInsets verticalSmallPadding =
      EdgeInsets.symmetric(vertical: verticalSmall);
  static const EdgeInsets verticalMediumPadding =
      EdgeInsets.symmetric(vertical: verticalMedium);
  static const EdgeInsets verticalLargePadding =
      EdgeInsets.symmetric(vertical: verticalLarge);
  static const EdgeInsets verticalXLargePadding =
      EdgeInsets.symmetric(vertical: verticalXLarge);
  static const EdgeInsets verticalXXLargePadding =
      EdgeInsets.symmetric(vertical: verticalXXLarge);
  static const EdgeInsets verticalXXXLargePadding =
      EdgeInsets.symmetric(vertical: verticalXXXLarge);

  static const EdgeInsets screenPaddingInsets =
      EdgeInsets.symmetric(horizontal: screenHorizontal, vertical: screenVertical);
}
```

### 3.5 Border Radius System

```dart
// lib/core/design_system/theme/app_border_radius.dart

class AppBorderRadius {
  const AppBorderRadius._();

  static const double xSmall = 4.0;
  static const double small = 8.0;
  static const double medium = 12.0;
  static const double large = 16.0;
  static const double xLarge = 20.0;
  static const double xxLarge = 24.0;
  static const double xxxLarge = 32.0;
  static const double circle = 999.0;

  static const BorderRadius xSmallRadius = BorderRadius.all(Radius.circular(xSmall));
  static const BorderRadius smallRadius = BorderRadius.all(Radius.circular(small));
  static const BorderRadius mediumRadius = BorderRadius.all(Radius.circular(medium));
  static const BorderRadius largeRadius = BorderRadius.all(Radius.circular(large));
  static const BorderRadius xLargeRadius = BorderRadius.all(Radius.circular(xLarge));
  static const BorderRadius xxLargeRadius = BorderRadius.all(Radius.circular(xxLarge));
  static const BorderRadius xxxLargeRadius = BorderRadius.all(Radius.circular(xxxLarge));
  static const BorderRadius circleRadius = BorderRadius.all(Radius.circular(circle));
}
```

### 3.6 Elevation System

```dart
// lib/core/design_system/theme/app_elevation.dart

class AppElevation {
  const AppElevation._();

  static const double level0 = 0.0;
  static const double level1 = 1.0;
  static const double level2 = 2.0;
  static const double level3 = 3.0;
  static const double level4 = 4.0;
  static const double level6 = 6.0;
  static const double level8 = 8.0;
  static const double level12 = 12.0;
  static const double level16 = 16.0;
  static const double level24 = 24.0;
}
```

### 3.7 Theme Data Configuration

```dart
// lib/core/design_system/theme/app_theme_data.dart

class AppThemeData {
  const AppThemeData._();

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.light,
      ),
      extensions: const [
        AppThemeColors.light,
      ],
      textTheme: _buildTextTheme(Brightness.light),
      appBarTheme: _buildAppBarTheme(Brightness.light),
      cardTheme: _buildCardTheme(Brightness.light),
      elevatedButtonTheme: _buildElevatedButtonTheme(Brightness.light),
      textButtonTheme: _buildTextButtonTheme(Brightness.light),
      outlinedButtonTheme: _buildOutlinedButtonTheme(Brightness.light),
      inputDecorationTheme: _buildInputDecorationTheme(Brightness.light),
      bottomNavigationBarTheme: _buildBottomNavigationBarTheme(Brightness.light),
      floatingActionButtonTheme: _buildFloatingActionButtonTheme(Brightness.light),
      chipTheme: _buildChipTheme(Brightness.light),
      dialogTheme: _buildDialogTheme(Brightness.light),
      bottomSheetTheme: _buildBottomSheetTheme(Brightness.light),
      dividerTheme: _buildDividerTheme(Brightness.light),
      progressIndicatorTheme: _buildProgressIndicatorTheme(Brightness.light),
      snackBarTheme: _buildSnackBarTheme(Brightness.light),
      tabBarTheme: _buildTabBarTheme(Brightness.light),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.grey900,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.dark,
      ),
      extensions: const [
        AppThemeColors.dark,
      ],
      textTheme: _buildTextTheme(Brightness.dark),
      appBarTheme: _buildAppBarTheme(Brightness.dark),
      cardTheme: _buildCardTheme(Brightness.dark),
      elevatedButtonTheme: _buildElevatedButtonTheme(Brightness.dark),
      textButtonTheme: _buildTextButtonTheme(Brightness.dark),
      outlinedButtonTheme: _buildOutlinedButtonTheme(Brightness.dark),
      inputDecorationTheme: _buildInputDecorationTheme(Brightness.dark),
      bottomNavigationBarTheme: _buildBottomNavigationBarTheme(Brightness.dark),
      floatingActionButtonTheme: _buildFloatingActionButtonTheme(Brightness.dark),
      chipTheme: _buildChipTheme(Brightness.dark),
      dialogTheme: _buildDialogTheme(Brightness.dark),
      bottomSheetTheme: _buildBottomSheetTheme(Brightness.dark),
      dividerTheme: _buildDividerTheme(Brightness.dark),
      progressIndicatorTheme: _buildProgressIndicatorTheme(Brightness.dark),
      snackBarTheme: _buildSnackBarTheme(Brightness.dark),
      tabBarTheme: _buildTabBarTheme(Brightness.dark),
    );
  }

  static TextTheme _buildTextTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return GoogleFonts.tajawalTextTheme().copyWith(
      displayLarge: AppTextStyles.displayLarge.copyWith(
        color: isDark ? AppColors.white : AppColors.textPrimary,
      ),
      displayMedium: AppTextStyles.displayMedium.copyWith(
        color: isDark ? AppColors.white : AppColors.textPrimary,
      ),
      displaySmall: AppTextStyles.displaySmall.copyWith(
        color: isDark ? AppColors.white : AppColors.textPrimary,
      ),
      headlineLarge: AppTextStyles.headlineLarge.copyWith(
        color: isDark ? AppColors.white : AppColors.textPrimary,
      ),
      headlineMedium: AppTextStyles.headlineMedium.copyWith(
        color: isDark ? AppColors.white : AppColors.textPrimary,
      ),
      headlineSmall: AppTextStyles.headlineSmall.copyWith(
        color: isDark ? AppColors.white : AppColors.textPrimary,
      ),
      titleLarge: AppTextStyles.titleLarge.copyWith(
        color: isDark ? AppColors.white : AppColors.textPrimary,
      ),
      titleMedium: AppTextStyles.titleMedium.copyWith(
        color: isDark ? AppColors.white : AppColors.textPrimary,
      ),
      titleSmall: AppTextStyles.titleSmall.copyWith(
        color: isDark ? AppColors.white : AppColors.textPrimary,
      ),
      bodyLarge: AppTextStyles.bodyLarge.copyWith(
        color: isDark ? AppColors.grey300 : AppColors.textPrimary,
      ),
      bodyMedium: AppTextStyles.bodyMedium.copyWith(
        color: isDark ? AppColors.grey300 : AppColors.textPrimary,
      ),
      bodySmall: AppTextStyles.bodySmall.copyWith(
        color: isDark ? AppColors.grey400 : AppColors.textSecondary,
      ),
      labelLarge: AppTextStyles.labelLarge.copyWith(
        color: isDark ? AppColors.grey300 : AppColors.textPrimary,
      ),
      labelMedium: AppTextStyles.labelMedium.copyWith(
        color: isDark ? AppColors.grey400 : AppColors.textSecondary,
      ),
      labelSmall: AppTextStyles.labelSmall.copyWith(
        color: isDark ? AppColors.grey500 : AppColors.textTertiary,
      ),
    );
  }

  static AppBarTheme _buildAppBarTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return AppBarTheme(
      backgroundColor: isDark ? AppColors.grey800 : AppColors.white,
      foregroundColor: isDark ? AppColors.white : AppColors.textPrimary,
      elevation: 0,
      centerTitle: false,
      iconTheme: IconThemeData(
        color: isDark ? AppColors.white : AppColors.primary,
      ),
      actionsIconTheme: IconThemeData(
        color: isDark ? AppColors.white : AppColors.primary,
      ),
      titleTextStyle: AppTextStyles.titleLarge.copyWith(
        color: isDark ? AppColors.white : AppColors.textPrimary,
      ),
    );
  }

  static CardTheme _buildCardTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return CardTheme(
      color: isDark ? AppColors.grey800 : AppColors.white,
      elevation: AppElevation.level1,
      shape: RoundedRectangleBorder(
        borderRadius: AppBorderRadius.mediumRadius,
      ),
      margin: AppSpacing.horizontalLargePadding + AppSpacing.verticalSmallPadding,
    );
  }

  static ElevatedButtonThemeData _buildElevatedButtonTheme(Brightness brightness) {
    return ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textOnPrimary,
        disabledBackgroundColor: AppColors.grey300,
        disabledForegroundColor: AppColors.textDisabled,
        elevation: AppElevation.level0,
        minimumSize: const Size(double.infinity, 48),
        padding: AppSpacing.horizontalLargePadding + AppSpacing.verticalMediumPadding,
        shape: RoundedRectangleBorder(
          borderRadius: AppBorderRadius.mediumRadius,
        ),
        textStyle: AppTextStyles.labelLarge,
      ),
    );
  }

  static TextButtonThemeData _buildTextButtonTheme(Brightness brightness) {
    return TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        disabledForegroundColor: AppColors.textDisabled,
        padding: AppSpacing.horizontalLargePadding + AppSpacing.verticalMediumPadding,
        shape: RoundedRectangleBorder(
          borderRadius: AppBorderRadius.mediumRadius,
        ),
        textStyle: AppTextStyles.labelLarge,
      ),
    );
  }

  static OutlinedButtonThemeData _buildOutlinedButtonTheme(Brightness brightness) {
    return OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        disabledForegroundColor: AppColors.textDisabled,
        side: const BorderSide(color: AppColors.primary),
        minimumSize: const Size(double.infinity, 48),
        padding: AppSpacing.horizontalLargePadding + AppSpacing.verticalMediumPadding,
        shape: RoundedRectangleBorder(
          borderRadius: AppBorderRadius.mediumRadius,
        ),
        textStyle: AppTextStyles.labelLarge,
      ),
    );
  }

  static InputDecorationTheme _buildInputDecorationTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return InputDecorationTheme(
      filled: true,
      fillColor: isDark ? AppColors.grey700 : AppColors.grey100,
      contentPadding: AppSpacing.horizontalLargePadding + AppSpacing.verticalMediumPadding,
      border: OutlineInputBorder(
        borderRadius: AppBorderRadius.mediumRadius,
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: AppBorderRadius.mediumRadius,
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: AppBorderRadius.mediumRadius,
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: AppBorderRadius.mediumRadius,
        borderSide: const BorderSide(color: AppColors.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: AppBorderRadius.mediumRadius,
        borderSide: const BorderSide(color: AppColors.error, width: 2),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: AppBorderRadius.mediumRadius,
        borderSide: BorderSide.none,
      ),
      labelStyle: AppTextStyles.bodyMedium.copyWith(
        color: isDark ? AppColors.grey400 : AppColors.textSecondary,
      ),
      hintStyle: AppTextStyles.bodyMedium.copyWith(
        color: isDark ? AppColors.grey500 : AppColors.textTertiary,
      ),
      errorStyle: AppTextStyles.bodySmall.copyWith(
        color: AppColors.error,
      ),
    );
  }

  static BottomNavigationBarThemeData _buildBottomNavigationBarTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return BottomNavigationBarThemeData(
      backgroundColor: isDark ? AppColors.grey800 : AppColors.white,
      selectedItemColor: AppColors.primary,
      unselectedItemColor: isDark ? AppColors.grey400 : AppColors.grey600,
      selectedLabelStyle: AppTextStyles.labelMedium,
      unselectedLabelStyle: AppTextStyles.labelMedium,
      type: BottomNavigationBarType.fixed,
      elevation: AppElevation.level3,
    );
  }

  static FloatingActionButtonThemeData _buildFloatingActionButtonTheme(Brightness brightness) {
    return FloatingActionButtonThemeData(
      backgroundColor: AppColors.primary,
      foregroundColor: AppColors.textOnPrimary,
      elevation: AppElevation.level3,
      shape: RoundedRectangleBorder(
        borderRadius: AppBorderRadius.largeRadius,
      ),
    );
  }

  static ChipThemeData _buildChipTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return ChipThemeData(
      backgroundColor: isDark ? AppColors.grey700 : AppColors.grey100,
      deleteIconColor: isDark ? AppColors.grey400 : AppColors.grey600,
      disabledColor: isDark ? AppColors.grey800 : AppColors.grey200,
      selectedColor: AppColors.primary.withOpacity(0.12),
      secondarySelectedColor: AppColors.primary.withOpacity(0.12),
      padding: AppSpacing.horizontalMediumPadding,
      labelStyle: AppTextStyles.labelMedium.copyWith(
        color: isDark ? AppColors.white : AppColors.textPrimary,
      ),
      secondaryLabelStyle: AppTextStyles.labelMedium.copyWith(
        color: isDark ? AppColors.white : AppColors.textPrimary,
      ),
      brightness: brightness,
      shape: RoundedRectangleBorder(
        borderRadius: AppBorderRadius.smallRadius,
      ),
    );
  }

  static DialogTheme _buildDialogTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return DialogTheme(
      backgroundColor: isDark ? AppColors.grey800 : AppColors.white,
      elevation: AppElevation.level8,
      shape: RoundedRectangleBorder(
        borderRadius: AppBorderRadius.largeRadius,
      ),
      titleTextStyle: AppTextStyles.titleLarge.copyWith(
        color: isDark ? AppColors.white : AppColors.textPrimary,
      ),
      contentTextStyle: AppTextStyles.bodyMedium.copyWith(
        color: isDark ? AppColors.grey300 : AppColors.textPrimary,
      ),
    );
  }

  static BottomSheetThemeData _buildBottomSheetTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return BottomSheetThemeData(
      backgroundColor: isDark ? AppColors.grey800 : AppColors.white,
      elevation: AppElevation.level8,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppBorderRadius.large),
        ),
      ),
    );
  }

  static DividerThemeData _buildDividerTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return DividerThemeData(
      color: isDark ? AppColors.grey700 : AppColors.grey200,
      thickness: 1,
      space: 1,
    );
  }

  static ProgressIndicatorThemeData _buildProgressIndicatorTheme(Brightness brightness) {
    return const ProgressIndicatorThemeData(
      color: AppColors.primary,
      linearTrackColor: AppColors.grey200,
      circularTrackColor: AppColors.grey200,
    );
  }

  static SnackBarThemeData _buildSnackBarTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return SnackBarThemeData(
      backgroundColor: isDark ? AppColors.grey800 : AppColors.grey900,
      contentTextStyle: AppTextStyles.bodyMedium.copyWith(
        color: AppColors.white,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: AppBorderRadius.mediumRadius,
      ),
      behavior: SnackBarBehavior.floating,
      elevation: AppElevation.level6,
    );
  }

  static TabBarTheme _buildTabBarTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return TabBarTheme(
      labelColor: AppColors.primary,
      unselectedLabelColor: isDark ? AppColors.grey400 : AppColors.grey600,
      labelStyle: AppTextStyles.labelLarge,
      unselectedLabelStyle: AppTextStyles.labelLarge,
      indicator: UnderlineTabIndicator(
        borderSide: const BorderSide(
          color: AppColors.primary,
          width: 2,
        ),
        insets: AppSpacing.horizontalLargePadding,
      ),
    );
  }
}

// lib/core/design_system/theme/app_theme.dart

class AppTheme {
  const AppTheme._();

  static ThemeData of(BuildContext context) {
    return Theme.of(context);
  }

  static AppThemeColors colors(BuildContext context) {
    return Theme.of(context).extension<AppThemeColors>()!;
  }

  static TextTheme textTheme(BuildContext context) {
    return Theme.of(context).textTheme;
  }

  static bool isDark(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark;
  }

  static bool isLight(BuildContext context) {
    return Theme.of(context).brightness == Brightness.light;
  }
}

// Extension for easy access to theme extensions

extension ThemeExtension on BuildContext {
  AppThemeColors get themeColors => Theme.of(this).extension<AppThemeColors>()!;
}
```

### 3.8 Reusable Widget Components

#### 3.8.1 Core UI Components

The design system includes reusable components that follow the established theming:

```dart
// lib/core/design_system/widgets/app_button.dart

class AppButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool isDisabled;
  final bool isFullWidth;
  final ButtonType type;

  const AppButton({
    super.key,
    required this.text,
    this.onPressed,
    this.isLoading = false,
    this.isDisabled = false,
    this.isFullWidth = true,
    this.type = ButtonType.elevated,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !isLoading && !isDisabled;

    Widget button;
    switch (type) {
      case ButtonType.elevated:
        button = ElevatedButton(
          onPressed: enabled ? onPressed : null,
          child: _buildChild(context),
        );
        break;
      case ButtonType.text:
        button = TextButton(
          onPressed: enabled ? onPressed : null,
          child: _buildChild(context),
        );
        break;
      case ButtonType.outlined:
        button = OutlinedButton(
          onPressed: enabled ? onPressed : null,
          child: _buildChild(context),
        );
        break;
    }

    if (!isFullWidth) {
      return button;
    }

    return SizedBox(
      width: double.infinity,
      child: button,
    );
  }

  Widget _buildChild(BuildContext context) {
    if (isLoading) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppColors.white,
        ),
      );
    }
    return Text(text);
  }
}

enum ButtonType { elevated, text, outlined }

// lib/core/design_system/widgets/app_card.dart

class AppCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? backgroundColor;
  final double? elevation;
  final BorderRadius? borderRadius;
  final Border? border;

  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding,
    this.margin,
    this.backgroundColor,
    this.elevation,
    this.borderRadius,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final card = Card(
      color: backgroundColor,
      elevation: elevation ?? AppElevation.level1,
      shape: RoundedRectangleBorder(
        borderRadius: borderRadius ?? AppBorderRadius.mediumRadius,
        side: border ?? BorderSide.none,
      ),
      margin: margin ?? AppSpacing.horizontalLargePadding + AppSpacing.verticalSmallPadding,
      child: Padding(
        padding: padding ?? AppSpacing.allLarge,
        child: child,
      ),
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: borderRadius ?? AppBorderRadius.mediumRadius,
        child: card,
      );
    }

    return card;
  }
}

// lib/core/design_system/widgets/app_input_field.dart

class AppInputField extends StatelessWidget {
  final String? label;
  final String? hint;
  final String? initialValue;
  final TextEditingController? controller;
  final bool obscureText;
  final bool enabled;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onTap;
  final Widget? suffixIcon;
  final Widget? prefixIcon;
  final String? errorText;
  final int? maxLines;
  final int? maxLength;
  final bool readOnly;

  const AppInputField({
    super.key,
    this.label,
    this.hint,
    this.initialValue,
    this.controller,
    this.obscureText = false,
    this.enabled = true,
    this.keyboardType,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.suffixIcon,
    this.prefixIcon,
    this.errorText,
    this.maxLines = 1,
    this.maxLength,
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      initialValue: initialValue,
      obscureText: obscureText,
      enabled: enabled,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      onTap: onTap,
      maxLines: maxLines,
      maxLength: maxLength,
      readOnly: readOnly,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        errorText: errorText,
        suffixIcon: suffixIcon,
        prefixIcon: prefixIcon,
      ),
    );
  }
}

// lib/core/design_system/widgets/app_loading_indicator.dart

class AppLoadingIndicator extends StatelessWidget {
  final double? size;
  final Color? color;

  const AppLoadingIndicator({
    super.key,
    this.size,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size ?? 24,
      height: size ?? 24,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        valueColor: AlwaysStoppedAnimation<Color>(
          color ?? AppColors.primary,
        ),
      ),
    );
  }
}

// lib/core/design_system/widgets/app_error_view.dart

class AppErrorView extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const AppErrorView({
    super.key,
    required this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: AppSpacing.allLarge,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: AppColors.error,
            ),
            SizedBox(height: AppSpacing.verticalLarge),
            Text(
              message,
              style: AppTextStyles.bodyMedium,
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              SizedBox(height: AppSpacing.verticalLarge),
              AppButton(
                text: 'إعادة المحاولة',
                onPressed: onRetry,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// lib/core/design_system/widgets/app_empty_view.dart

class AppEmptyView extends StatelessWidget {
  final String message;
  final IconData? icon;

  const AppEmptyView({
    super.key,
    required this.message,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: AppSpacing.allLarge,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon ?? Icons.inbox_outlined,
              size: 64,
              color: AppColors.grey400,
            ),
            SizedBox(height: AppSpacing.verticalLarge),
            Text(
              message,
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
```

---

## 4. Migration Strategy

### 4.1 Migration Approach

The migration will be executed in phases to minimize disruption and ensure the application remains functional throughout the process.

#### 4.1.1 Phase 1: Foundation Setup (Week 1-2)

**Objectives:**
- Set up the new directory structure
- Implement the core design system
- Configure dependency injection for core components

**Tasks:**
1. Create new directory structure
2. Implement design system files:
   - `lib/core/design_system/theme/`
   - `lib/core/design_system/constants/`
   - `lib/core/design_system/widgets/`
3. Update `app.dart` to use new theme system
4. Set up core DI configuration

**Deliverables:**
- New directory structure in place
- Design system foundation implemented
- App runs with new theme (visual changes should be minimal)

#### 4.1.2 Phase 2: Core Components Migration (Week 3-4)

**Objectives:**
- Migrate shared models to domain layer
- Create reusable widget components
- Update router and navigation

**Tasks:**
1. Move shared models to appropriate feature domain layers
2. Create reusable widget components in design system
3. Update router to use new structure
4. Update shared widgets to use design system

**Deliverables:**
- Shared models properly organized
- Reusable components available
- Router updated
- Shared widgets using design system

#### 4.1.3 Phase 3: Feature Migration - Auth (Week 5)

**Objectives:**
- Refactor auth feature to Clean Architecture
- Migrate auth screens to use design system

**Tasks:**
1. Create auth feature structure:
   - Domain: entities, use cases, repository interfaces
   - Data: models, repository implementations, data sources
   - Presentation: BLoC, screens
2. Migrate auth screens to use design system
3. Update DI for auth feature
4. Test auth flow end-to-end

**Deliverables:**
- Auth feature fully refactored
- Auth screens using design system
- Auth flow working correctly

#### 4.1.4 Phase 4: Feature Migration - Orders (Week 6-7)

**Objectives:**
- Refactor orders feature to Clean Architecture
- Migrate orders screens to use design system

**Tasks:**
1. Create orders feature structure
2. Migrate order-related models
3. Implement use cases
4. Update repository implementations
5. Migrate screens to use design system
6. Update DI for orders feature
7. Test orders flow end-to-end

**Deliverables:**
- Orders feature fully refactored
- Orders screens using design system
- Orders flow working correctly

#### 4.1.5 Phase 5: Feature Migration - Inventory (Week 8)

**Objectives:**
- Refactor inventory feature to Clean Architecture
- Migrate inventory screens to use design system

**Tasks:**
1. Create inventory feature structure
2. Migrate inventory-related models
3. Implement use cases
4. Update repository implementations
5. Migrate screens to use design system
6. Update DI for inventory feature
7. Test inventory flow end-to-end

**Deliverables:**
- Inventory feature fully refactored
- Inventory screens using design system
- Inventory flow working correctly

#### 4.1.6 Phase 6: Feature Migration - Remaining Features (Week 9-11)

**Objectives:**
- Refactor remaining features to Clean Architecture
- Migrate remaining screens to use design system

**Features to migrate:**
- Entities
- Chat
- Notifications
- Profile
- Manager
- Rep
- Storage

**Tasks:**
1. For each feature:
   - Create feature structure
   - Migrate models
   - Implement use cases
   - Update repository implementations
   - Migrate screens to use design system
   - Update DI
   - Test feature end-to-end

**Deliverables:**
- All features fully refactored
- All screens using design system
- All features working correctly

#### 4.1.7 Phase 7: Cleanup and Optimization (Week 12)

**Objectives:**
- Remove old code
- Optimize performance
- Final testing

**Tasks:**
1. Remove old directory structure
2. Remove unused imports
3. Optimize dependency injection
4. Run comprehensive tests
5. Performance profiling and optimization
6. Update documentation

**Deliverables:**
- Clean codebase
- Optimized performance
- Updated documentation
- All tests passing

### 4.2 Migration Guidelines

#### 4.2.1 Code Migration Checklist

For each file being migrated:

- [ ] Identify the correct location in new structure
- [ ] Extract business logic into use cases
- [ ] Create repository interfaces in domain layer
- [ ] Implement repositories in data layer
- [ ] Update BLoC to use use cases
- [ ] Replace hardcoded styles with design system
- [ ] Update imports
- [ ] Test functionality
- [ ] Update DI configuration

#### 4.2.2 Style Migration Checklist

For each screen/component:

- [ ] Replace hardcoded colors with `AppColors`
- [ ] Replace hardcoded text styles with `AppTextStyles`
- [ ] Replace hardcoded spacing with `AppSpacing`
- [ ] Replace hardcoded border radius with `AppBorderRadius`
- [ ] Replace hardcoded elevation with `AppElevation`
- [ ] Use theme extensions where appropriate
- [ ] Test visual appearance
- [ ] Verify dark mode support

#### 4.2.3 Testing Strategy

**Unit Testing:**
- Test use cases in isolation
- Test repository implementations with mocks
- Test BLoC state transitions

**Integration Testing:**
- Test feature flows end-to-end
- Test navigation between features
- Test data flow from UI to data layer

**UI Testing:**
- Test visual appearance matches original
- Test responsive design
- Test dark mode
- Test RTL layout (Arabic)

### 4.3 Risk Mitigation

#### 4.3.1 Potential Risks

1. **Breaking Changes During Migration**
   - Risk: Application becomes non-functional
   - Mitigation: Migrate incrementally, test after each phase

2. **Visual Regression**
   - Risk: UI appearance changes unexpectedly
   - Mitigation: Use design system consistently, test visually after each screen migration

3. **Performance Degradation**
   - Risk: New architecture introduces performance issues
   - Mitigation: Profile performance throughout migration, optimize as needed

4. **Timeline Overrun**
   - Risk: Migration takes longer than expected
   - Mitigation: Prioritize critical features, defer non-essential work

#### 4.3.2 Rollback Strategy

- Maintain git branches for each phase
- Keep old code until migration is complete
- Test thoroughly before merging
- Have rollback plan for each phase

---

## 5. Rationale for Architectural Decisions

### 5.1 Clean Architecture Principles

#### 5.1.1 Why Clean Architecture?

**Benefits:**
1. **Separation of Concerns:** Each layer has a single responsibility
2. **Testability:** Business logic can be tested without UI or data dependencies
3. **Maintainability:** Changes in one layer don't affect others
4. **Scalability:** Easy to add new features without modifying existing code
5. **Flexibility:** Can swap implementations (e.g., different data sources) without affecting business logic

**Alignment with URA CORE:**
- Complex business logic across multiple features
- Need for consistent behavior across roles (verifier, manager, rep, storage)
- Frequent updates and new features
- Multiple data sources (Supabase, local storage)

#### 5.1.2 Dependency Rule

**Decision:** Dependencies must point inward, toward the domain layer.

**Rationale:**
- Domain layer contains core business logic that shouldn't depend on external factors
- Data layer can change (new APIs, databases) without affecting business logic
- Presentation layer can change (new UI frameworks) without affecting business logic
- Makes the codebase more resilient to change

**Implementation:**
- Domain layer defines interfaces (repositories)
- Data layer implements these interfaces
- Presentation layer uses domain use cases
- DI container wires everything together

### 5.2 Feature-Based Organization

#### 5.2.1 Why Feature-Based?

**Benefits:**
1. **Cohesion:** All code related to a feature is in one place
2. **Isolation:** Features can be developed and tested independently
3. **Onboarding:** New developers can understand a feature by looking at its folder
4. **Reusability:** Features can be extracted into separate packages if needed
5. **Scalability:** Easy to add new features without disrupting existing ones

**Alignment with URA CORE:**
- Distinct business features (auth, orders, inventory, chat, etc.)
- Different user roles interact with different features
- Features have independent business logic and data requirements

#### 5.2.2 Feature Structure

**Decision:** Each feature has domain, data, and presentation subfolders.

**Rationale:**
- Clear separation of concerns within features
- Easy to navigate and understand
- Consistent structure across all features
- Supports Clean Architecture principles

### 5.3 State Management Choice

#### 5.3.1 Why BLoC (Cubit)?

**Benefits:**
1. **Predictable State:** State changes are explicit and traceable
2. **Testability:** Easy to test BLoCs without UI
3. **Separation of Concerns:** UI logic separate from business logic
4. **Reactive:** Automatically updates UI when state changes
5. **Mature:** Well-established pattern with good tooling

**Alignment with URA CORE:**
- Already using BLoC/Cubit in current codebase
- Complex state management across features
- Need for real-time updates (Supabase subscriptions)
- Multiple stateful screens

#### 5.3.2 BLoC Location

**Decision:** BLoCs in presentation layer, using use cases from domain layer.

**Rationale:**
- BLoCs manage UI state (loading, error, success)
- Use cases contain business logic
- Clear separation between UI state and business logic
- BLoCs are thin, delegating to use cases

### 5.4 Design System Architecture

#### 5.4.1 Why Centralized Design System?

**Benefits:**
1. **Consistency:** All screens use the same styles
2. **Maintainability:** Update styles in one place
3. **Efficiency:** Reusable components reduce code duplication
4. **Scalability:** Easy to add new components
5. **Collaboration:** Designers and developers work from the same system

**Alignment with URA CORE:**
- Multiple screens with similar patterns
- Need for consistent branding
- Arabic RTL support required
- Dark mode support desired

#### 5.4.2 Color System Design

**Decision:** Semantic color naming (success, error, warning, info) + brand colors.

**Rationale:**
- Semantic colors communicate meaning (not just visual)
- Brand colors maintain identity
- Easy to update color schemes
- Supports theming (light/dark modes)

**Implementation:**
- `AppColors` class with all color constants
- Theme extensions for semantic access
- Support for light and dark themes

#### 5.4.3 Typography System Design

**Decision:** Material Design 3 typography scale + Google Fonts (Tajawal for Arabic).

**Rationale:**
- Material Design 3 provides established scale
- Tajawal is optimized for Arabic
- Consistent typography across app
- Supports RTL layout naturally

**Implementation:**
- `AppTextStyles` class with predefined styles
- Theme extensions for easy access
- Helper methods for customization

#### 5.4.4 Spacing System Design

**Decision:** 4-point scale (4, 8, 12, 16, 20, 24, 32) + named constants.

**Rationale:**
- Consistent spacing throughout app
- Easy to maintain and update
- Follows design best practices
- Reduces magic numbers in code

**Implementation:**
- `AppSpacing` class with spacing constants
- Helper methods for common patterns
- EdgeInsets helpers for convenience

#### 5.4.5 Reusable Components

**Decision:** Core components in design system (Button, Card, InputField, etc.).

**Rationale:**
- Reduces code duplication
- Ensures consistency
- Easy to update behavior
- Faster development

**Implementation:**
- Components in `lib/core/design_system/widgets/`
- Use design system theming
- Flexible and customizable
- Well-documented

### 5.5 Dependency Injection Strategy

#### 5.5.1 Why GetIt?

**Benefits:**
1. **Performance:** Fast dependency resolution
2. **Simplicity:** Easy to use and understand
3. **Flexibility:** Supports singleton and factory registrations
4. **Testability:** Easy to replace dependencies for testing
5. **Mature:** Well-established in Flutter community

**Alignment with URA CORE:**
- Already using GetIt in current codebase
- Complex dependency graph
- Need for singleton services (repositories, BLoCs)
- Testability requirements

#### 5.5.2 DI Organization

**Decision:** Separate DI files for core and features.

**Rationale:**
- Clear separation of concerns
- Easy to locate dependencies
- Supports feature independence
- Easier to maintain

**Implementation:**
- `core_injection.dart` for core dependencies
- `feature_injection.dart` for feature dependencies
- Barrel file for easy imports

### 5.6 Navigation Strategy

#### 5.6.1 Why GoRouter?

**Benefits:**
1. **Declarative:** Routes defined declaratively
2. **Deep Linking:** Built-in deep linking support
3. **Type Safety:** Strong typing for routes
4. **State Management:** Integrates with app state
5. **Modern:** Active development and community support

**Alignment with URA CORE:**
- Already using GoRouter in current codebase
- Complex navigation requirements
- Deep linking for auth callbacks
- Role-based navigation

#### 5.6.2 Route Organization

**Decision:** Centralized route definitions in router module.

**Rationale:**
- Single source of truth for routes
- Easy to manage navigation flow
- Supports route guards and redirects
- Clear navigation structure

### 5.7 Testing Strategy

#### 5.7.1 Why Multi-Level Testing?

**Decision:** Unit, integration, and UI tests.

**Rationale:**
- Unit tests: Test business logic in isolation
- Integration tests: Test feature flows
- UI tests: Test visual appearance and interactions
- Comprehensive coverage ensures quality

#### 5.7.2 Test Organization

**Decision:** Tests mirror source structure.

**Rationale:**
- Easy to find tests for specific code
- Clear relationship between code and tests
- Supports test-driven development
- Encourages testing

### 5.8 Performance Considerations

#### 5.8.1 Why Performance Focus?

**Decision:** Optimize for performance throughout migration.

**Rationale:**
- Flutter apps need to be performant
- Complex features can impact performance
- User experience depends on performance
- Mobile devices have limited resources

#### 5.8.2 Optimization Strategies

**Decision:** Profile and optimize continuously.

**Rationale:**
- Catch performance issues early
- Ensure smooth user experience
- Maintain app responsiveness
- Support older devices

### 5.9 Internationalization Strategy

#### 5.9.1 Why RTL Support?

**Decision:** Full RTL support for Arabic language.

**Rationale:**
- Primary language is Arabic
- RTL layout required
- Text direction matters
- Cultural alignment

#### 5.9.2 Implementation Approach

**Decision:** Use Flutter's built-in RTL support + Tajawal font.

**Rationale:**
- Flutter has excellent RTL support
- Tajawal is optimized for Arabic
- Minimal additional code needed
- Consistent with Material Design

---

## 6. Implementation Timeline

### 6.1 Overall Timeline

**Total Duration:** 12 weeks

| Phase | Duration | Status |
|-------|----------|--------|
| Phase 1: Foundation Setup | 2 weeks | Pending |
| Phase 2: Core Components | 2 weeks | Pending |
| Phase 3: Auth Feature | 1 week | Pending |
| Phase 4: Orders Feature | 2 weeks | Pending |
| Phase 5: Inventory Feature | 1 week | Pending |
| Phase 6: Remaining Features | 3 weeks | Pending |
| Phase 7: Cleanup & Optimization | 1 week | Pending |

### 6.2 Weekly Breakdown

**Week 1-2: Phase 1 - Foundation Setup**
- Create directory structure
- Implement design system
- Update app.dart
- Setup core DI

**Week 3-4: Phase 2 - Core Components**
- Migrate shared models
- Create reusable widgets
- Update router
- Update shared widgets

**Week 5: Phase 3 - Auth Feature**
- Refactor auth feature
- Migrate auth screens
- Test auth flow

**Week 6-7: Phase 4 - Orders Feature**
- Refactor orders feature
- Migrate orders screens
- Test orders flow

**Week 8: Phase 5 - Inventory Feature**
- Refactor inventory feature
- Migrate inventory screens
- Test inventory flow

**Week 9-11: Phase 6 - Remaining Features**
- Refactor entities feature
- Refactor chat feature
- Refactor notifications feature
- Refactor profile feature
- Refactor manager feature
- Refactor rep feature
- Refactor storage feature

**Week 12: Phase 7 - Cleanup & Optimization**
- Remove old code
- Optimize performance
- Final testing
- Update documentation

---

## 7. Success Criteria

### 7.1 Technical Criteria

- [ ] All features migrated to Clean Architecture
- [ ] All screens using design system
- [ ] No hardcoded values in UI code
- [ ] All tests passing
- [ ] Performance maintained or improved
- [ ] Code coverage > 80%
- [ ] No memory leaks
- [ ] No visual regressions

### 7.2 Functional Criteria

- [ ] All existing features working correctly
- [ ] Auth flow working
- [ ] Orders flow working
- [ ] Inventory flow working
- [ ] Chat flow working
- [ ] Notifications working
- [ ] All user roles working
- [ ] Deep linking working

### 7.3 Quality Criteria

- [ ] Code follows Clean Architecture principles
- [ ] Code follows Flutter best practices
- [ ] Code is well-documented
- [ ] Code is maintainable
- [ ] Code is testable
- [ ] Design system is consistent
- [ ] UI is visually identical to original

---

## 8. Conclusion

This comprehensive refactoring plan provides a clear roadmap for transforming the URA CORE Flutter application into a well-architected, maintainable, and scalable codebase. The proposed Clean Architecture structure, combined with a centralized design system, will:

1. **Improve Code Quality:** Clear separation of concerns, reduced coupling, increased cohesion
2. **Enhance Maintainability:** Easier to understand, modify, and extend
3. **Increase Testability:** Business logic isolated and testable
4. **Ensure Consistency:** Centralized design system for UI consistency
5. **Support Growth:** Scalable architecture for future features
6. **Maintain Performance:** Optimized for mobile devices
7. **Preserve Functionality:** All existing features continue to work

The phased migration approach minimizes risk and allows for continuous testing and validation throughout the process. By following this plan, the URA CORE application will be positioned for long-term success and continued evolution.

---

## 9. Next Steps

1. **Review and Approve:** Stakeholders review this proposal and provide feedback
2. **Prioritize Phases:** Confirm priority order for feature migration
3. **Allocate Resources:** Assign developers to each phase
4. **Set Up Infrastructure:** Prepare development and testing environments
5. **Begin Phase 1:** Start foundation setup
6. **Monitor Progress:** Track progress against timeline
7. **Adjust as Needed:** Adapt plan based on learnings and feedback

---

## 10. Appendices

### Appendix A: File Migration Mapping

| Current File | New Location |
|--------------|--------------|
| `lib/shared/models/order.dart` | `lib/features/orders/domain/entities/order.dart` |
| `lib/shared/models/profile.dart` | `lib/features/auth/domain/entities/user.dart` |
| `lib/shared/models/inventory_item.dart` | `lib/features/inventory/domain/entities/inventory_item.dart` |
| `lib/shared/models/entity.dart` | `lib/features/entities/domain/entities/entity.dart` |
| `lib/shared/models/chat_message.dart` | `lib/features/chat/domain/entities/chat_message.dart` |
| `lib/shared/models/chat_thread.dart` | `lib/features/chat/domain/entities/chat_thread.dart` |
| `lib/shared/models/app_notification.dart` | `lib/features/notifications/domain/entities/app_notification.dart` |
| `lib/shared/order_status_theme.dart` | `lib/features/shared/domain/value_objects/order_status_theme.dart` |
| `lib/shared/widgets/order_list_tile.dart` | `lib/features/shared/presentation/widgets/order_list_tile.dart` |
| `lib/shared/widgets/receipt_viewer_screen.dart` | `lib/features/shared/presentation/widgets/receipt_viewer_screen.dart` |

### Appendix B: Design System Usage Examples

#### Example 1: Using Colors

```dart
// Before
Container(
  color: Colors.teal,
)

// After
Container(
  color: AppColors.primary,
)
```

#### Example 2: Using Text Styles

```dart
// Before
Text(
  'Hello',
  style: TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.bold,
  ),
)

// After
Text(
  'Hello',
  style: AppTextStyles.titleMedium,
)
```

#### Example 3: Using Spacing

```dart
// Before
Padding(
  padding: EdgeInsets.all(16),
  child: ...,
)

// After
Padding(
  padding: AppSpacing.allLarge,
  child: ...,
)
```

#### Example 4: Using Theme Extensions

```dart
// Before
Container(
  color: Theme.of(context).brightness == Brightness.dark
      ? Colors.grey[800]
      : Colors.white,
)

// After
Container(
  color: context.themeColors.surface,
)
```

### Appendix C: Clean Architecture Examples

#### Example 1: Use Case

```dart
// lib/features/orders/domain/usecases/get_orders_usecase.dart

class GetOrdersUseCase {
  final OrderRepository repository;

  GetOrdersUseCase(this.repository);

  Future<AppResult<List<Order>>> call() {
    return repository.fetchAllOrders();
  }
}
```

#### Example 2: BLoC Using Use Case

```dart
// lib/features/orders/presentation/bloc/orders_bloc.dart

class OrdersBloc extends Bloc<OrdersEvent, OrdersState> {
  final GetOrdersUseCase getOrdersUseCase;

  OrdersBloc(this.getOrdersUseCase) : super(OrdersInitial()) {
    on<LoadOrders>(_onLoadOrders);
  }

  Future<void> _onLoadOrders(
    LoadOrders event,
    Emitter<OrdersState> emit,
  ) async {
    emit(OrdersLoading());
    final result = await getOrdersUseCase();
    switch (result) {
      case AppSuccess(:final data):
        emit(OrdersLoaded(data));
      case AppFailure(:final error):
        emit(OrdersError(error.message));
    }
  }
}
```

#### Example 3: Repository Implementation

```dart
// lib/features/orders/data/repositories/order_repository_impl.dart

class OrderRepositoryImpl implements OrderRepository {
  final OrderRemoteDataSource remoteDataSource;
  final OrderLocalDataSource localDataSource;

  OrderRepositoryImpl(
    this.remoteDataSource,
    this.localDataSource,
  );

  @override
  Future<AppResult<List<Order>>> fetchAllOrders() async {
    try {
      final orderModels = await remoteDataSource.fetchAllOrders();
      final orders = orderModels.map((model) => model.toEntity()).toList();
      return AppSuccess(orders);
    } catch (e) {
      return AppFailure(ErrorHandler.handle(e));
    }
  }
}
```

---

**Document Version:** 1.0
**Last Updated:** 2025-01-12
**Author:** Architecture Team
**Status:** Draft - Pending Review