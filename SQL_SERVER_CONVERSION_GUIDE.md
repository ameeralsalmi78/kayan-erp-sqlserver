# 🔄 دليل تحويل KAYAN ERP من Supabase إلى SQL Server

## 📋 نظرة عامة

هذا الدليل الشامل للمبرمج المحلي لتحويل نظام KAYAN ERP من Supabase (PostgreSQL) إلى SQL Server.

---

## 📊 تحليل البنية الحالية

### **ما هو موجود:**
- ✅ **28 ملف Migration** (PostgreSQL)
- ✅ **24 ملف يستخدم Supabase**
- ✅ **نظام مصادقة Supabase Auth**
- ✅ **Row Level Security (RLS)**
- ✅ **~40 جدول في قاعدة البيانات**
- ✅ **51 مكون React**

### **ما يحتاج تحويل:**
1. **قاعدة البيانات**: من PostgreSQL إلى SQL Server
2. **المصادقة**: من Supabase Auth إلى نظام مخصص
3. **RLS**: من PostgreSQL RLS إلى Stored Procedures
4. **مكتبة الاتصال**: من `@supabase/supabase-js` إلى `mssql`
5. **الاستعلامات**: من PostgreSQL إلى T-SQL

---

## 🎯 خطة التحويل الكاملة

### **المرحلة 1: إعداد البيئة**

#### **1.1 المتطلبات:**
```bash
# Node.js LTS (18+)
node --version

# SQL Server (2019+ أو SQL Server Express)
# SQL Server Management Studio (SSMS)

# مكتبات Node.js المطلوبة:
npm install mssql
npm install bcryptjs
npm install jsonwebtoken
npm uninstall @supabase/supabase-js
```

#### **1.2 إنشاء قاعدة البيانات:**
```sql
-- في SSMS، نفذ:
CREATE DATABASE KAYAN_ERP;
GO

USE KAYAN_ERP;
GO
```

---

### **المرحلة 2: تحويل Schema (الجداول)**

#### **2.1 الفروقات الرئيسية:**

| PostgreSQL | SQL Server |
|-----------|-----------|
| `uuid` | `UNIQUEIDENTIFIER` |
| `text` | `NVARCHAR(MAX)` |
| `timestamptz` | `DATETIMEOFFSET` |
| `jsonb` | `NVARCHAR(MAX)` (JSON) |
| `gen_random_uuid()` | `NEWID()` |
| `now()` | `GETDATE()` |
| `auth.uid()` | `CAST(SESSION_CONTEXT(N'user_id') AS UNIQUEIDENTIFIER)` |

#### **2.2 مثال تحويل جدول:**

**قبل (PostgreSQL):**
```sql
CREATE TABLE users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email text UNIQUE NOT NULL,
  created_at timestamptz DEFAULT now()
);
```

**بعد (SQL Server):**
```sql
CREATE TABLE users (
  id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
  email NVARCHAR(255) UNIQUE NOT NULL,
  created_at DATETIMEOFFSET DEFAULT GETDATE()
);
```

---

### **المرحلة 3: تحويل RLS إلى Stored Procedures**

#### **3.1 مفهوم RLS في PostgreSQL:**
```sql
-- PostgreSQL RLS:
CREATE POLICY "Users can read own data"
  ON users FOR SELECT
  TO authenticated
  USING (auth.uid() = id);
```

#### **3.2 البديل في SQL Server:**

**أ) Session Context للمستخدم الحالي:**
```sql
-- عند تسجيل الدخول، احفظ user_id:
EXEC sp_set_session_context 'user_id', @current_user_id;
```

**ب) Stored Procedures مع صلاحيات:**
```sql
CREATE PROCEDURE sp_GetUserProfile
    @user_id UNIQUEIDENTIFIER
AS
BEGIN
    DECLARE @current_user_id UNIQUEIDENTIFIER =
        CAST(SESSION_CONTEXT(N'user_id') AS UNIQUEIDENTIFIER);

    -- تحقق من الصلاحية
    IF @user_id != @current_user_id
    BEGIN
        RAISERROR('Unauthorized access', 16, 1);
        RETURN;
    END

    SELECT * FROM users WHERE id = @user_id;
END
GO
```

**ج) Security Predicates (SQL Server 2016+):**
```sql
-- إنشاء دالة للتحقق
CREATE FUNCTION dbo.fn_UserSecurity(@user_id UNIQUEIDENTIFIER)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN SELECT 1 AS allowed
WHERE @user_id = CAST(SESSION_CONTEXT(N'user_id') AS UNIQUEIDENTIFIER);
GO

-- تطبيق Security Policy
CREATE SECURITY POLICY UserSecurityPolicy
ADD FILTER PREDICATE dbo.fn_UserSecurity(id) ON dbo.users,
ADD BLOCK PREDICATE dbo.fn_UserSecurity(id) ON dbo.users AFTER INSERT
WITH (STATE = ON);
GO
```

---

### **المرحلة 4: نظام المصادقة (Authentication)**

#### **4.1 إنشاء جداول المصادقة:**
```sql
-- جدول المستخدمين
CREATE TABLE auth_users (
    id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    email NVARCHAR(255) UNIQUE NOT NULL,
    password_hash NVARCHAR(255) NOT NULL,
    email_confirmed BIT DEFAULT 0,
    created_at DATETIMEOFFSET DEFAULT GETDATE(),
    updated_at DATETIMEOFFSET DEFAULT GETDATE()
);

-- جدول الجلسات (Sessions)
CREATE TABLE auth_sessions (
    id UNIQUEIDENTIFIER PRIMARY KEY DEFAULT NEWID(),
    user_id UNIQUEIDENTIFIER NOT NULL REFERENCES auth_users(id),
    token NVARCHAR(500) NOT NULL UNIQUE,
    expires_at DATETIMEOFFSET NOT NULL,
    created_at DATETIMEOFFSET DEFAULT GETDATE(),
    CONSTRAINT FK_Sessions_Users FOREIGN KEY (user_id) REFERENCES auth_users(id) ON DELETE CASCADE
);

-- Index للأداء
CREATE INDEX IX_auth_sessions_token ON auth_sessions(token);
CREATE INDEX IX_auth_sessions_expires ON auth_sessions(expires_at);
```

#### **4.2 Stored Procedures للمصادقة:**

**تسجيل مستخدم جديد:**
```sql
CREATE PROCEDURE sp_RegisterUser
    @email NVARCHAR(255),
    @password NVARCHAR(255),
    @new_user_id UNIQUEIDENTIFIER OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    -- تحقق من وجود البريد
    IF EXISTS (SELECT 1 FROM auth_users WHERE email = @email)
    BEGIN
        RAISERROR('Email already exists', 16, 1);
        RETURN;
    END

    -- أنشئ hash للباسورد (يتم في Node.js باستخدام bcrypt)
    -- هنا نفترض أن password_hash يأتي جاهز

    SET @new_user_id = NEWID();

    INSERT INTO auth_users (id, email, password_hash)
    VALUES (@new_user_id, @email, @password); -- @password هو الـ hash

    -- أنشئ profile للمستخدم
    INSERT INTO profiles (id, email)
    VALUES (@new_user_id, @email);
END
GO
```

**تسجيل الدخول:**
```sql
CREATE PROCEDURE sp_LoginUser
    @email NVARCHAR(255),
    @user_id UNIQUEIDENTIFIER OUTPUT,
    @password_hash NVARCHAR(255) OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        @user_id = id,
        @password_hash = password_hash
    FROM auth_users
    WHERE email = @email AND email_confirmed = 1;

    IF @user_id IS NULL
    BEGIN
        RAISERROR('Invalid credentials', 16, 1);
        RETURN;
    END
END
GO
```

**إنشاء جلسة:**
```sql
CREATE PROCEDURE sp_CreateSession
    @user_id UNIQUEIDENTIFIER,
    @token NVARCHAR(500),
    @expires_at DATETIMEOFFSET
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO auth_sessions (user_id, token, expires_at)
    VALUES (@user_id, @token, @expires_at);
END
GO
```

---

### **المرحلة 5: تحويل الكود (Frontend)**

#### **5.1 إنشاء Database Client:**

**ملف: `src/lib/database.ts`**
```typescript
import sql from 'mssql';

const config: sql.config = {
  server: process.env.VITE_SQL_SERVER || 'localhost',
  database: process.env.VITE_SQL_DATABASE || 'KAYAN_ERP',
  user: process.env.VITE_SQL_USER,
  password: process.env.VITE_SQL_PASSWORD,
  options: {
    encrypt: true, // للـ Azure
    trustServerCertificate: true // للتطوير المحلي
  }
};

let pool: sql.ConnectionPool | null = null;

export async function getConnection() {
  if (!pool) {
    pool = await sql.connect(config);
  }
  return pool;
}

export async function executeQuery<T>(
  query: string,
  params?: any
): Promise<T[]> {
  const connection = await getConnection();
  const request = connection.request();

  // إضافة المعاملات
  if (params) {
    Object.keys(params).forEach(key => {
      request.input(key, params[key]);
    });
  }

  const result = await request.query(query);
  return result.recordset as T[];
}

export async function executeProcedure<T>(
  procedureName: string,
  params?: any
): Promise<T> {
  const connection = await getConnection();
  const request = connection.request();

  // إضافة المعاملات
  if (params) {
    Object.keys(params).forEach(key => {
      const param = params[key];
      request.input(key, param.type, param.value);
    });
  }

  const result = await request.execute(procedureName);
  return result.recordset as T;
}
```

#### **5.2 تحويل Authentication Context:**

**ملف: `src/contexts/AuthContext.tsx`**
```typescript
import React, { createContext, useContext, useState, useEffect } from 'react';
import * as bcrypt from 'bcryptjs';
import * as jwt from 'jsonwebtoken';
import { executeProcedure } from '../lib/database';

interface User {
  id: string;
  email: string;
  role?: string;
}

interface AuthContextType {
  user: User | null;
  signIn: (email: string, password: string) => Promise<void>;
  signUp: (email: string, password: string) => Promise<void>;
  signOut: () => Promise<void>;
  loading: boolean;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);

  // تحقق من الجلسة عند التحميل
  useEffect(() => {
    checkSession();
  }, []);

  async function checkSession() {
    try {
      const token = localStorage.getItem('auth_token');
      if (!token) {
        setLoading(false);
        return;
      }

      // تحقق من صحة الـ token
      const decoded = jwt.verify(token, process.env.VITE_JWT_SECRET!) as User;
      setUser(decoded);
    } catch (error) {
      console.error('Session check failed:', error);
      localStorage.removeItem('auth_token');
    } finally {
      setLoading(false);
    }
  }

  async function signUp(email: string, password: string) {
    try {
      // Hash password
      const passwordHash = await bcrypt.hash(password, 10);

      // استدعاء stored procedure
      const result = await executeProcedure('sp_RegisterUser', {
        email: { type: sql.NVarChar, value: email },
        password: { type: sql.NVarChar, value: passwordHash }
      });

      // تسجيل دخول تلقائي
      await signIn(email, password);
    } catch (error) {
      throw error;
    }
  }

  async function signIn(email: string, password: string) {
    try {
      // الحصول على بيانات المستخدم
      const result = await executeProcedure('sp_LoginUser', {
        email: { type: sql.NVarChar, value: email }
      });

      if (!result || result.length === 0) {
        throw new Error('Invalid credentials');
      }

      const userData = result[0];

      // تحقق من الباسورد
      const isValid = await bcrypt.compare(password, userData.password_hash);
      if (!isValid) {
        throw new Error('Invalid credentials');
      }

      // إنشاء JWT token
      const token = jwt.sign(
        { id: userData.id, email: userData.email },
        process.env.VITE_JWT_SECRET!,
        { expiresIn: '7d' }
      );

      // حفظ الجلسة في قاعدة البيانات
      await executeProcedure('sp_CreateSession', {
        user_id: { type: sql.UniqueIdentifier, value: userData.id },
        token: { type: sql.NVarChar, value: token },
        expires_at: { type: sql.DateTimeOffset, value: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000) }
      });

      // حفظ في localStorage
      localStorage.setItem('auth_token', token);

      setUser({ id: userData.id, email: userData.email });
    } catch (error) {
      throw error;
    }
  }

  async function signOut() {
    const token = localStorage.getItem('auth_token');
    if (token) {
      try {
        // حذف الجلسة من قاعدة البيانات
        await executeProcedure('sp_DeleteSession', {
          token: { type: sql.NVarChar, value: token }
        });
      } catch (error) {
        console.error('Sign out error:', error);
      }
    }

    localStorage.removeItem('auth_token');
    setUser(null);
  }

  return (
    <AuthContext.Provider value={{ user, signIn, signUp, signOut, loading }}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  const context = useContext(AuthContext);
  if (!context) {
    throw new Error('useAuth must be used within AuthProvider');
  }
  return context;
}
```

---

### **المرحلة 6: تحويل استعلامات المكونات**

#### **6.1 مثال: تحويل InvoicesList**

**قبل (Supabase):**
```typescript
const { data: invoices, error } = await supabase
  .from('invoices')
  .select('*')
  .eq('organization_id', user?.organization_id)
  .order('created_at', { ascending: false });
```

**بعد (SQL Server):**
```typescript
import { executeQuery } from '../lib/database';

const invoices = await executeQuery(`
  SELECT * FROM invoices
  WHERE organization_id = @orgId
  ORDER BY created_at DESC
`, {
  orgId: user?.organization_id
});
```

#### **6.2 استخدام Stored Procedures:**
```typescript
const invoices = await executeProcedure('sp_GetInvoices', {
  organization_id: { type: sql.UniqueIdentifier, value: user?.organization_id },
  limit: { type: sql.Int, value: 50 }
});
```

---

## 📁 هيكل الملفات الجديد

```
project/
├── src/
│   ├── lib/
│   │   ├── database.ts           (NEW - SQL Server client)
│   │   └── supabase.ts           (DELETE)
│   ├── contexts/
│   │   └── AuthContext.tsx       (MODIFY - Custom auth)
│   ├── components/               (MODIFY ALL - استعلامات جديدة)
│   └── ...
│
├── database/                     (NEW FOLDER)
│   ├── migrations/               (ملفات SQL Server)
│   ├── stored-procedures/        (جميع الـ SPs)
│   └── setup.sql                 (سكريبت الإعداد الكامل)
│
├── .env                          (MODIFY - متغيرات SQL Server)
└── package.json                  (MODIFY - مكتبات جديدة)
```

---

## 🔧 ملف .env الجديد

```env
# SQL Server Configuration
VITE_SQL_SERVER=localhost
VITE_SQL_DATABASE=KAYAN_ERP
VITE_SQL_USER=sa
VITE_SQL_PASSWORD=YourPassword123!
VITE_SQL_PORT=1433

# JWT Secret (أنشئ واحد قوي)
VITE_JWT_SECRET=your-super-secret-jwt-key-here-minimum-32-characters

# App Configuration
VITE_APP_NAME=KAYAN ERP
VITE_APP_URL=http://localhost:5173
```

---

## ⚠️ تحديات وحلول

### **1. فقدان API التلقائي (Supabase Auto API)**
**الحل:** إنشاء API Layer باستخدام:
- Express.js server
- أو استخدام Stored Procedures مباشرة

### **2. فقدان Realtime (Live Updates)**
**الحل:**
- استخدام WebSockets مع Socket.io
- أو Polling بفترات منتظمة

### **3. RLS المعقد**
**الحل:**
- استخدام Security Predicates
- أو التحقق من الصلاحيات في Stored Procedures

### **4. حجم العمل الكبير**
**الحل:**
- تحويل تدريجي (module by module)
- البدء بالـ Authentication والجداول الأساسية

---

## 📝 قائمة التحقق (Checklist)

### **قاعدة البيانات:**
- [ ] إنشاء قاعدة بيانات KAYAN_ERP
- [ ] تحويل جميع الجداول (40+)
- [ ] إنشاء Stored Procedures للمصادقة
- [ ] إنشاء SPs لـ CRUD operations
- [ ] تطبيق Security Policies
- [ ] إضافة Indexes للأداء

### **الكود:**
- [ ] تثبيت mssql package
- [ ] إنشاء database.ts client
- [ ] تحويل AuthContext
- [ ] تحويل جميع المكونات (51)
- [ ] اختبار كل مكون
- [ ] معالجة الأخطاء

### **الاختبار:**
- [ ] اختبار التسجيل والدخول
- [ ] اختبار الصلاحيات
- [ ] اختبار جميع الـ CRUD operations
- [ ] اختبار الأداء
- [ ] اختبار الأمان

---

## 🚀 خطة التنفيذ الموصى بها

### **الأسبوع 1: الإعداد والمصادقة**
1. إعداد SQL Server
2. إنشاء جداول المصادقة
3. تحويل AuthContext
4. اختبار التسجيل والدخول

### **الأسبوع 2-3: الجداول الأساسية**
1. تحويل جداول: organizations, branches, profiles
2. تحويل جداول: customers, suppliers, products
3. إنشاء SPs للعمليات الأساسية
4. تحويل المكونات المرتبطة

### **الأسبوع 4-5: المبيعات والمشتريات**
1. تحويل جداول: invoices, sales, purchases
2. إنشاء SPs للفواتير
3. تحويل مكونات: InvoiceForm, InvoicesList, POSSystem

### **الأسبوع 6: المحاسبة والتقارير**
1. تحويل جداول: accounts, transactions
2. إنشاء SPs للتقارير
3. تحويل مكونات: FinancialDashboard, ReportsAnalytics

### **الأسبوع 7: الاختبار والتحسين**
1. اختبار شامل
2. تحسين الأداء
3. معالجة الأخطاء
4. توثيق

---

## 📚 موارد مفيدة

- [SQL Server Documentation](https://docs.microsoft.com/sql/sql-server/)
- [mssql npm package](https://www.npmjs.com/package/mssql)
- [Row-Level Security in SQL Server](https://docs.microsoft.com/sql/relational-databases/security/row-level-security)
- [bcryptjs Documentation](https://www.npmjs.com/package/bcryptjs)
- [jsonwebtoken Documentation](https://www.npmjs.com/package/jsonwebtoken)

---

## 💰 تقدير التكلفة (الوقت)

- **صغير (تحويل أساسي):** 3-4 أسابيع
- **متوسط (تحويل كامل):** 6-8 أسابيع
- **كبير (مع تحسينات):** 10-12 أسبوع

**يعتمد على:**
- خبرة المبرمج بـ SQL Server و T-SQL
- عدد ساعات العمل اليومية
- مستوى الاختبار المطلوب

---

## ✅ الخلاصة

هذا مشروع كبير يحتاج:
1. فهم عميق لـ SQL Server و T-SQL
2. خبرة بـ React و TypeScript
3. معرفة بأنظمة المصادقة والأمان
4. صبر واختبار دقيق

**الملفات التالية ستساعدك:**
- `SQL_SERVER_MIGRATIONS/` - جميع الـ migrations محولة
- `SQL_SERVER_PROCEDURES/` - جميع الـ SPs جاهزة
- `SQL_SERVER_SETUP.sql` - سكريبت إعداد كامل

---

**حظاً موفقاً! 🚀**
