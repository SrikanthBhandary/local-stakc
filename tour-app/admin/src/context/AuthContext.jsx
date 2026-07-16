import {
    createContext,
    useContext,
    useEffect,
    useState
} from "react";

import * as authApi from "../api/auth";

const AuthContext = createContext(null);

export function AuthProvider({ children }) {

    const [authenticated, setAuthenticated] = useState(false);

    const [loading, setLoading] = useState(true);

    useEffect(() => {

        setAuthenticated(authApi.isAuthenticated());

        setLoading(false);

    }, []);

    async function login(username, password) {

        await authApi.login(username, password);

        setAuthenticated(true);

    }

    function logout() {
        localStorage.removeItem("accessToken");
        localStorage.removeItem("idToken");
        localStorage.removeItem("refreshToken");


        authApi.logout();

        setAuthenticated(false);

    }

    async function refresh() {

        try {

            await authApi.refreshAccessToken();

            setAuthenticated(true);

        } catch (err) {

            console.error(err);

            logout();

        }

    }

    const value = {

        authenticated,

        loading,

        login,

        logout,

        refresh,

        accessToken: authApi.getAccessToken(),

        idToken: authApi.getIdToken(),
        

    };

    return (

        <AuthContext.Provider value={value}>

            {children}

        </AuthContext.Provider>

    );

}

export function useAuth() {

    const context = useContext(AuthContext);

    if (!context) {

        throw new Error(
            "useAuth must be used inside AuthProvider"
        );

    }

    return context;

}
