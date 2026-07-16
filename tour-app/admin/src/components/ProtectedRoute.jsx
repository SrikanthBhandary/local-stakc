import { Navigate } from "react-router-dom";

import { useAuth } from "../context/AuthContext";

import Spinner from "./Spinner";

export default function ProtectedRoute({ children }) {

    const auth = useAuth();

    if (auth.loading) {

        return <Spinner />;

    }

    if (!auth.authenticated) {

        return <Navigate to="/" replace />;

    }

    return children;

}