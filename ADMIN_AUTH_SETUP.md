# Admin Authentication & Access Control Setup

## Overview
The admin website now has a complete authentication system with:
- **Manager Role**: Can create admin accounts and manage all admins
- **Admin Role**: Can access admin panel but cannot create other admins
- **Login System**: Secure authentication using Firebase Auth
- **Access Control**: Role-based permissions

## Initial Setup (Create Manager Account)

### Step 1: Create Manager Account in Firebase Console

1. Go to Firebase Console: https://console.firebase.google.com
2. Select your project: `marketsafe-e57cf`
3. Go to **Authentication** → **Users**
4. Click **Add user**
5. Enter manager email and password
6. Click **Add user**
7. **Copy the User UID** (you'll need this)

### Step 2: Add Manager to Firestore

1. Go to **Firestore Database** in Firebase Console
2. Create collection: `adminUsers`
3. Create document with ID = **Manager's User UID** (from Step 1)
4. Add these fields:
   ```json
   {
     "email": "manager@marketsafe.com",
     "name": "Manager Name",
     "role": "manager",
     "permissions": {
       "canApproveUsers": true,
       "canRejectUsers": true,
     "canViewUserData": true,
       "canDeleteUsers": true,
       "canCreateAdmins": true
     },
     "createdAt": "2024-01-01T00:00:00Z",
     "lastLoginAt": null
   }
   ```

### Step 3: Test Login

1. Open `admin.html` in browser
2. Login with manager email and password
3. You should see the admin panel
4. You should see "Admin Management" tab (only for managers)

## Creating Admin Accounts (Manager Only)

### As Manager:

1. Login to admin panel
2. Click **"Admin Management"** tab
3. Click **"Add New Admin"** button
4. Fill in:
   - **Email**: Admin's email address
   - **Name**: Admin's full name
   - **Password**: Temporary password (admin should change it)
5. Click **"Create Admin"**
6. The system will:
   - Create Firebase Auth user
   - Add admin to Firestore `adminUsers` collection
   - Send credentials to admin (or you can share manually)

### Admin Permissions

Admins have these permissions by default:
- ✅ Can approve/reject users
- ✅ Can view user data
- ❌ Cannot create other admins (manager only)
- ❌ Cannot delete users (manager only)

## Roles Explained

### Manager Role
- **Role**: `"manager"`
- **Permissions**: All permissions including `canCreateAdmins: true`
- **Can**: Create admin accounts, manage all admins, full access

### Admin Role
- **Role**: `"admin"`
- **Permissions**: Standard admin permissions (no `canCreateAdmins`)
- **Can**: Approve/reject users, view data
- **Cannot**: Create other admins

## Security Notes

1. **Manager account is powerful** - Keep credentials secure
2. **Admins cannot create other admins** - Only manager can
3. **All actions are logged** - Check Firestore for audit trail
4. **Firebase Auth required** - Must authenticate to access panel
5. **Role checked on every page load** - Prevents unauthorized access

## Troubleshooting

**"Access Denied" error:**
- Check if user exists in `adminUsers` collection
- Verify role is "manager" or "admin"
- Check Firebase Auth user exists

**Cannot create admin:**
- Verify you're logged in as manager (role: "manager")
- Check `canCreateAdmins` permission is true

**Login not working:**
- Verify Firebase Auth is enabled in Firebase Console
- Check email/password are correct
- Check browser console for errors

