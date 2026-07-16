import { Routes, Route, Navigate } from "react-router-dom";

import LoginPage from "./pages/LoginPage";
import DashboardPage from "./pages/DashboardPage";

import ProtectedRoute from "./components/ProtectedRoute";

export default function App() {

    return (

        <Routes>

            {/* Login */}

            <Route
                path="/"
                element={<LoginPage />}
            />

            {/* Protected Admin Dashboard */}

            <Route
                path="/dashboard"
                element={
                    <ProtectedRoute>

                        <DashboardPage />

                    </ProtectedRoute>
                }
            />

            {/* Unknown Routes */}

            <Route
                path="*"
                element={<Navigate to="/" replace />}
            />

        </Routes>

    );

}