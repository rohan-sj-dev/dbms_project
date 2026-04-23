import { useAuth } from '../context/AuthContext';
import { useApi } from '../hooks';
import { getCustomerLoans, getCustomerLoanApps } from '../api';
import { PageHeader, Card, DataTable, Badge, Spinner, ErrorBox } from '../components/UI';

const appStatusColor = { submitted: 'amber', under_review: 'blue', approved: 'green', rejected: 'red', disbursed: 'green', withdrawn: 'red' };
const appStatusLabel = { submitted: 'Submitted', under_review: 'Reviewed by Employee', approved: 'Approved', rejected: 'Rejected' };
const loanStatusColor = { pending: 'amber', active: 'green', closed: 'default', npa: 'red', written_off: 'red', foreclosed: 'red' };

const loanColumns = [
  { key: 'loan_id', label: 'Loan ID' },
  { key: 'loan_type', label: 'Type', render: r => <Badge variant="purple">{r.loan_type}</Badge> },
  { key: 'applied_amount', label: 'Applied', render: r => `₹${Number(r.applied_amount || 0).toLocaleString('en-IN')}` },
  { key: 'sanctioned_amount', label: 'Sanctioned', render: r => r.sanctioned_amount ? `₹${Number(r.sanctioned_amount).toLocaleString('en-IN')}` : '—' },
  { key: 'interest_rate', label: 'Rate %', render: r => r.interest_rate || r.base_interest_rate },
  { key: 'tenure_months', label: 'Tenure (mo)' },
  { key: 'emi_amount', label: 'EMI', render: r => r.emi_amount ? `₹${Number(r.emi_amount).toLocaleString('en-IN')}` : '—' },
  { key: 'application_status', label: 'App Status', render: r => <Badge variant={appStatusColor[r.application_status]}>{r.application_status}</Badge> },
  { key: 'status', label: 'Status', render: r => <Badge variant={loanStatusColor[r.status]}>{r.status}</Badge> },
  { key: 'outstanding_principal', label: 'Outstanding', render: r => r.outstanding_principal ? `₹${Number(r.outstanding_principal).toLocaleString('en-IN')}` : '—' },
];

const appColumns = [
  { key: 'application_id', label: 'App ID' },
  { key: 'requested_amount', label: 'Amount', render: r => `₹${Number(r.requested_amount || 0).toLocaleString('en-IN')}` },
  { key: 'purpose', label: 'Purpose' },
  { key: 'status', label: 'Status', render: r => <Badge variant={appStatusColor[r.status] || 'default'}>{appStatusLabel[r.status] || r.status}</Badge> },
  { key: 'officer_name', label: 'Officer' },
  { key: 'application_date', label: 'Applied', render: r => r.application_date?.slice(0, 10) },
];

export default function CustomerLoansPage() {
  const { auth } = useAuth();
  const cid = auth.user.customer_id;
  const loans = useApi(() => getCustomerLoans(cid), [cid]);
  const apps  = useApi(() => getCustomerLoanApps(cid), [cid]);

  return (
    <>
      <PageHeader title="My Loans" />

      <p className="text-xs font-semibold text-gray-400 uppercase tracking-wider mb-3">Applications</p>
      <Card className="mb-6">
        {apps.loading ? <Spinner /> :
         apps.error ? <ErrorBox message={apps.error} onRetry={apps.refetch} /> :
          <DataTable columns={appColumns} rows={apps.data || []} emptyMsg="No loan applications yet." />}
      </Card>

      <p className="text-xs font-semibold text-gray-400 uppercase tracking-wider mb-3">Active & Past Loans</p>
      <Card>
        {loans.loading ? <Spinner /> :
         loans.error ? <ErrorBox message={loans.error} onRetry={loans.refetch} /> :
          <DataTable columns={loanColumns} rows={loans.data || []} emptyMsg="No loans on record. Applications appear above." />}
      </Card>
    </>
  );
}
