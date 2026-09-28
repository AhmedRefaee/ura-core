import { useState, type FormEvent } from 'react';
import { signIn } from '../hooks/useAuth';

export default function Login() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    setSubmitting(true);
    setError(null);
    const { error } = await signIn(email, password);
    setSubmitting(false);
    if (error) setError(error);
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-surface">
      <form onSubmit={handleSubmit} className="w-full max-w-md bg-surface-card rounded-card border border-border-subtle p-8 shadow-sm">
        <h1 className="text-xl font-semibold text-text-high mb-1">تسجيل الدخول إلى النظام</h1>
        <p className="text-sm text-text-low mb-6">منظومة إدارة التوريد والطلبات والمستودعات</p>

        <label htmlFor="email" className="block text-sm text-text-medium mb-1">اسم المستخدم أو البريد المؤسسي</label>
        <input
          id="email"
          type="text"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          className="w-full h-9 px-3 mb-4 rounded-input border border-border-subtle focus:border-primary focus:outline-none"
        />

        <label htmlFor="password" className="block text-sm text-text-medium mb-1">كلمة المرور</label>
        <input
          id="password"
          type="password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          className="w-full h-9 px-3 mb-4 rounded-input border border-border-subtle focus:border-primary focus:outline-none"
        />

        {error && <p className="text-error text-sm mb-4">{error}</p>}

        <button
          type="submit"
          disabled={submitting}
          className="w-full h-11 rounded-button bg-primary-fill text-white font-semibold disabled:opacity-60"
        >
          دخول إلى النظام
        </button>
      </form>
    </div>
  );
}
