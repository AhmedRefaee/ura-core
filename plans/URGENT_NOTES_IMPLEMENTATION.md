# Urgent Notes Feature - Implementation Complete

## 📋 Overview

The **Urgent Notes** feature has been successfully implemented in your URA CORE application. This feature allows Representatives (Reps) to create urgent notes at any stage of an order workflow, which require Verifier review and reply before the Rep can proceed to the next stage.

---

## 🎯 What Was Implemented

### **Two Categories of Notes**

1. **Regular Notes** (existing)
   - Simple comments
   - No blocking
   - Stored in `audit_log.notes`

2. **Urgent Notes** (new)
   - Requires Verifier review & reply
   - Blocks Rep from proceeding to next stage
   - Notifies Verifier
   - Stored in new `urgent_notes` table

---

## 📊 Database Changes

### **New Table: `urgent_notes`**

```sql
CREATE TABLE urgent_notes (
  id UUID PRIMARY KEY,
  order_id UUID NOT NULL,
  stage order_status NOT NULL,
  message TEXT NOT NULL,
  created_by UUID NOT NULL,
  created_at TIMESTAMPTZ,
  is_resolved BOOLEAN DEFAULT FALSE,
  resolved_by UUID,
  resolved_at TIMESTAMPTZ,
  reply TEXT
);
```

### **New RPC Functions**

1. `create_urgent_note()` - Rep creates urgent note
2. `resolve_urgent_note()` - Verifier resolves with reply
3. `get_pending_urgent_notes()` - Get pending notes for order
4. `get_all_pending_urgent_notes()` - Get all pending notes (Verifier dashboard)
5. `check_urgent_notes_block()` - Check if order is blocked
6. `get_pending_urgent_notes_count()` - Get total pending count

### **Modified RPC Functions**

- `start_move()` - Now checks for blocking urgent notes
- `mark_delivered()` - Now checks for blocking urgent notes

---

## 📱 Flutter Implementation

### **New Files Created**

1. **[`lib/shared/models/urgent_note.dart`](lib/shared/models/urgent_note.dart)**
   - `UrgentNote` model
   - `UrgentNotesBlockStatus` model

2. **[`lib/features/verifier/data/urgent_notes_repository.dart`](lib/features/verifier/data/urgent_notes_repository.dart)**
   - Repository for urgent notes operations
   - Real-time subscriptions

3. **[`lib/features/verifier/logic/urgent_notes_cubit.dart`](lib/features/verifier/logic/urgent_notes_cubit.dart)**
   - State management for urgent notes

4. **[`lib/features/verifier/ui/urgent_notes_screen.dart`](lib/features/verifier/ui/urgent_notes_screen.dart)**
   - Verifier dashboard for reviewing urgent notes

### **Modified Files**

1. **[`lib/core/di/injection.dart`](lib/core/di/injection.dart)**
   - Registered `UrgentNotesRepository`
   - Registered `UrgentNotesCubit`
   - Updated `RepOrderDetailCubit` registration

2. **[`lib/features/rep/logic/rep_order_detail_cubit.dart`](lib/features/rep/logic/rep_order_detail_cubit.dart)**
   - Added urgent notes to state
   - Added blocking status to state
   - Added `createUrgentNote()` method
   - Added `canProceedToNextStage` getter

3. **[`lib/features/rep/ui/rep_order_detail_screen.dart`](lib/features/rep/ui/rep_order_detail_screen.dart)**
   - Added `_UrgentNotesSection` widget
   - Added `_UrgentNoteCard` widget
   - Added blocking indicator
   - Updated action buttons to check blocking status

4. **[`lib/features/verifier/ui/verifier_home_screen.dart`](lib/features/verifier/ui/verifier_home_screen.dart)**
   - Added notification badge for urgent notes
   - Added `_UrgentNotesNotification` widget

5. **[`lib/features/manager/ui/task_detail_screen.dart`](lib/features/manager/ui/task_detail_screen.dart)**
   - Added `_OrderUrgentNotesSection` widget
   - Displays urgent notes in order details

---

## 🚀 How to Use

### **For Representatives (Reps)**

1. **Create Urgent Note:**
   - Open any order detail screen
   - Click "إضافة" (Add) button in the "الملاحظات العاجلة" (Urgent Notes) section
   - Enter your urgent message
   - Click "إرسال" (Send)

2. **View Blocking Status:**
   - If blocked, you'll see a red warning card
   - Action buttons will be disabled
   - Warning message: "لا يمكن المتابعة: X ملاحظة عاجلة بانتظار الرد"

3. **View Verifier Reply:**
   - Once Verifier replies, the note card turns green
   - You can see the reply in the note card
   - You can now proceed to the next stage

### **For Verifiers**

1. **View Notification:**
   - Red badge on notification icon shows pending count
   - Click notification icon to open urgent notes screen

2. **Review Urgent Notes:**
   - See all pending urgent notes
   - Each note shows:
     - Stage (assigned, picked_up, on_the_move)
     - Rep name
     - Order ID
     - Message
     - Time created

3. **Resolve Urgent Note:**
   - Click "رد وحل الملاحظة" (Reply and Resolve)
   - Enter your reply
   - Click "إرسال الرد" (Send Reply)
   - Note is marked as resolved
   - Rep is unblocked and can proceed

---

## 🔒 Blocking Mechanism

### **How It Works**

1. **Rep Creates Urgent Note:**
   - Note is saved with `is_resolved = FALSE`
   - Current stage is recorded

2. **Rep Tries to Proceed:**
   - `start_move()` or `mark_delivered()` is called
   - RPC function checks for unresolved notes at current stage
   - If found, returns error with pending count
   - Action button remains disabled

3. **Verifier Resolves Note:**
   - Note is updated with `is_resolved = TRUE`
   - Reply is saved
   - Rep can now proceed

### **Stages Where Blocking Occurs**

- **assigned** → Blocks `markPickedUp()`
- **picked_up** → Blocks `startMove()`
- **on_the_move** → Blocks `markDelivered()`

---

## 📊 Real-time Updates

### **Supabase Realtime**

- `urgent_notes` table is published to realtime
- Verifier dashboard auto-refreshes when new notes arrive
- Rep order detail screen auto-updates when notes are resolved

### **Notification Badge**

- Shows count of pending urgent notes
- Updates in real-time
- Displays "99+" if count exceeds 99

---

## 🎨 UI Features

### **Rep Order Detail Screen**

- **Urgent Notes Section:**
  - Shows all urgent notes for the order
  - Color-coded: Orange (pending), Green (resolved)
  - Shows stage, time, message, and reply

- **Blocking Indicator:**
  - Red warning card when blocked
  - Shows pending count
  - Clear message about why blocked

- **Action Buttons:**
  - Disabled when blocked
  - Warning message explains blocking reason

### **Verifier Home Screen**

- **Notification Badge:**
  - Red badge on notification icon
  - Shows pending count
  - Auto-updates

### **Urgent Notes Screen (Verifier)**

- **List View:**
  - All pending urgent notes
  - Stage badges
  - Rep names
  - Order IDs
  - Messages
  - Timestamps

- **Reply Dialog:**
  - Shows original message
  - Text field for reply
  - Send button

### **Task Detail Screen (Manager/Verifier)**

- **Urgent Notes Section:**
  - Shows all urgent notes for the order
  - Color-coded cards
  - Shows replies if resolved

---

## 🗄️ Database Migration

To deploy this feature, run the SQL migration:

```bash
# In Supabase SQL Editor
# Run the contents of: database/migrations/urgent_notes.sql
```

This will:
- Create `urgent_notes` table
- Create indexes
- Enable RLS policies
- Create RPC functions
- Modify existing RPC functions
- Enable realtime publication

---

## ✅ Testing Checklist

### **Rep Workflow**

- [ ] Create urgent note at assigned stage
- [ ] Verify blocking indicator appears
- [ ] Verify action button is disabled
- [ ] Wait for Verifier to resolve
- [ ] Verify note shows as resolved
- [ ] Verify action button is enabled
- [ ] Proceed to next stage

### **Verifier Workflow**

- [ ] See notification badge with count
- [ ] Open urgent notes screen
- [ ] View all pending notes
- [ ] Reply to a note
- [ ] Verify note is resolved
- [ ] Verify count decreases

### **Blocking Mechanism**

- [ ] Create note at assigned stage
- [ ] Try to mark as picked up → Should fail
- [ ] Resolve note
- [ ] Try to mark as picked up → Should succeed
- [ ] Create note at picked_up stage
- [ ] Try to start move → Should fail
- [ ] Resolve note
- [ ] Try to start move → Should succeed

### **Real-time Updates**

- [ ] Create note as Rep
- [ ] Verify Verifier sees notification immediately
- [ ] Resolve note as Verifier
- [ ] Verify Rep sees resolution immediately

---

## 📝 Notes

- **Arabic UI:** All UI text is in Arabic
- **RTL Support:** Proper right-to-left layout
- **Error Handling:** Comprehensive error messages
- **Loading States:** Proper loading indicators
- **Empty States:** Friendly empty state messages

---

## 🎯 Next Steps

1. **Deploy Database Migration:**
   - Run [`database/migrations/urgent_notes.sql`](database/migrations/urgent_notes.sql) in Supabase

2. **Test the Feature:**
   - Follow the testing checklist above
   - Test all user roles
   - Test all stages

3. **Optional Enhancements:**
   - Push notifications for urgent notes
   - Email notifications to Verifier
   - Priority levels for urgent notes
   - Attachment support for urgent notes

---

## 📞 Support

If you encounter any issues:
1. Check Supabase logs for RPC function errors
2. Verify RLS policies are correct
3. Check Flutter console for error messages
4. Ensure realtime is enabled in Supabase

---

**Implementation Date:** April 12, 2026
**Developer:** AI Assistant (GLM-4.7)
**Project:** URA CORE - Inventory & Logistics Management System
