import { NavLink } from 'react-router-dom';
import { useAuth } from '../context/AuthContext';

const managerBankingLinks = [
  { to: '/',                  label: 'Dashboard' },
  { to: '/customers',         label: 'Customers' },
  { to: '/accounts',          label: 'Accounts' },
  { to: '/transactions',      label: 'Transactions' },
  { to: '/loans',             label: 'Loans' },
  { to: '/loan-applications', label: 'Loan Applications' },
  { to: '/transfers',         label: 'Transfers' },
  { to: '/employees',         label: 'Employees' },
  { to: '/hr-updates',        label: 'HR Updates' },
  { to: '/branches',          label: 'Branches' },
  { to: '/acid-demo',         label: 'ACID Demo' },
  { to: '/change-password',   label: 'Change Password' },
];

const vcsLinks = [
  { to: '/vcs',             label: 'VCS Dashboard' },
  { to: '/vcs/commits',     label: 'Commits' },
  { to: '/vcs/branches',    label: 'Branches' },
  { to: '/vcs/tags',        label: 'Tags' },
  { to: '/vcs/diff',        label: 'Diff' },
  { to: '/vcs/blame',       label: 'Blame' },
  { to: '/vcs/time-travel', label: 'Time Travel' },
  { to: '/vcs/rollback',    label: 'Rollback' },
];

const employeeLinks = [
  { to: '/',                  label: 'Dashboard' },
  { to: '/my-customers',      label: 'My Customers' },
  { to: '/my-accounts',       label: 'Customer Accounts' },
  { to: '/my-transactions',   label: 'Transactions' },
  { to: '/my-loans',          label: 'Managed Loans' },
  { to: '/loan-applications', label: 'Loan Applications' },
  { to: '/profile',           label: 'My Profile' },
  { to: '/change-password',   label: 'Change Password' },
];

const customerLinks = [
  { to: '/',                label: 'Dashboard' },
  { to: '/my-accounts',     label: 'My Accounts' },
  { to: '/my-transactions', label: 'My Transactions' },
  { to: '/my-loans',        label: 'My Loans' },
  { to: '/my-transfers',    label: 'My Transfers' },
  { to: '/profile',         label: 'My Profile' },
  { to: '/change-password', label: 'Change Password' },
];

function SideLink({ to, label }) {
  return (
    <NavLink
      to={to}
      end={to === '/' || to === '/vcs'}
      className={({ isActive }) =>
        `flex items-center px-3 py-2 rounded-lg text-sm transition-colors
         ${isActive
           ? 'bg-indigo-50 text-indigo-700 font-semibold'
           : 'text-gray-600 hover:bg-gray-100 hover:text-gray-900'}`
      }
    >
      <span>{label}</span>
    </NavLink>
  );
}

const roleColors = {
  manager:  'bg-indigo-100 text-indigo-700',
  employee: 'bg-emerald-100 text-emerald-700',
  customer: 'bg-amber-100 text-amber-700',
};

export default function Sidebar() {
  const { auth, logout } = useAuth();
  const role = auth?.role;
  const user = auth?.user;

  return (
    <aside className="w-60 shrink-0 border-r border-gray-200 bg-white h-screen overflow-y-auto sticky top-0 flex flex-col">
      <div className="px-5 py-5">
        <h1 className="text-lg font-bold text-gray-900 tracking-tight">BankVCS</h1>
        <p className="text-xs text-gray-400 mt-0.5">Git-like DB Versioning</p>
      </div>

      {/* Role badge */}
      <div className="px-4 mb-3">
        <div className={`flex items-center px-3 py-2 rounded-lg text-xs font-semibold ${roleColors[role]}`}>
          <span className="capitalize">{role}</span>
          <span className="text-[10px] font-normal opacity-70 truncate ml-auto">{user?.full_name}</span>
        </div>
      </div>

      <nav className="px-3 space-y-1 flex-1">
        {role === 'manager' && (
          <>
            <p className="px-3 pt-3 pb-1 text-[11px] font-semibold text-gray-400 uppercase tracking-wider">Banking</p>
            {managerBankingLinks.map((l) => <SideLink key={l.to} {...l} />)}
            <p className="px-3 pt-5 pb-1 text-[11px] font-semibold text-gray-400 uppercase tracking-wider">Version Control</p>
            {vcsLinks.map((l) => <SideLink key={l.to} {...l} />)}
          </>
        )}

        {role === 'employee' && (
          <>
            <p className="px-3 pt-3 pb-1 text-[11px] font-semibold text-gray-400 uppercase tracking-wider">Employee Portal</p>
            {employeeLinks.map((l) => <SideLink key={l.to} {...l} />)}
          </>
        )}

        {role === 'customer' && (
          <>
            <p className="px-3 pt-3 pb-1 text-[11px] font-semibold text-gray-400 uppercase tracking-wider">Customer Portal</p>
            {customerLinks.map((l) => <SideLink key={l.to} {...l} />)}
          </>
        )}
      </nav>

      <div className="px-3 py-4 border-t border-gray-100">
        <button
          onClick={logout}
          className="flex items-center w-full px-3 py-2 rounded-lg text-sm text-red-600 hover:bg-red-50 transition-colors cursor-pointer"
        >
          <span>Sign Out</span>
        </button>
      </div>
    </aside>
  );
}
