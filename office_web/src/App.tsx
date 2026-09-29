import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { ProtectedRoute } from './components/ProtectedRoute';
import Login from './pages/Login';
import Orders from './pages/Orders';
import OrderDetailPage from './pages/OrderDetailPage';

export default function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/login" element={<Login />} />
        <Route
          path="/orders/:orderId?"
          element={
            <ProtectedRoute>
              <Orders />
            </ProtectedRoute>
          }
        />
        {/* Singular /order/:id, distinct from /orders/:orderId? (the list +
            side panel) -- opens the same detail content as its own full
            page, e.g. in a new tab via the panel's "open in its own page" link. */}
        <Route
          path="/order/:orderId"
          element={
            <ProtectedRoute>
              <OrderDetailPage />
            </ProtectedRoute>
          }
        />
        <Route path="/" element={<Navigate to="/orders" replace />} />
      </Routes>
    </BrowserRouter>
  );
}
