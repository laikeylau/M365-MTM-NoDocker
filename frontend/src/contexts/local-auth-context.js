/**
 * Local Authentication Context for CIPP
 * 
 * Self-contained authentication - no Azure AD dependency.
 * Users are stored in the API backend (Azurite Table Storage).
 * First registered user automatically becomes admin.
 * 
 * This replaces both SWA auth and MSAL auth.
 */

import { createContext, useContext, useEffect, useState, useCallback } from "react";
import axios from "axios";

export const LocalAuthContext = createContext(null);

export function LocalAuthProvider({ children }) {
  const [isAuthenticated, setIsAuthenticated] = useState(false);
  const [user, setUser] = useState(null);
  const [token, setToken] = useState(null);
  const [isLoading, setIsLoading] = useState(true);

  // Check for existing token in localStorage on mount
  useEffect(() => {
    const initAuth = async () => {
      try {
        const savedToken = localStorage.getItem("cipp_token");
        const savedUser = localStorage.getItem("cipp_user");
        if (savedToken && savedUser) {
          try {
            const userData = JSON.parse(savedUser);
            const valid = await verifyToken(savedToken);
            if (valid) {
              setToken(savedToken);
              setUser(userData);
              setIsAuthenticated(true);
              return;
            }
          } catch {
            // Token verification failed — fall through to API auth
          }
          localStorage.removeItem("cipp_token");
          localStorage.removeItem("cipp_user");
        }

        // Fallback: authenticate via /api/me (cipp-server mock auth)
        const resp = await axios.get("/api/me");
        const principal = resp.data?.clientPrincipal;
        if (principal?.userRoles?.length > 0) {
          const nameClaim = principal.claims?.find((c) => c.typ === "name");
          const derivedUser = {
            email: principal.userDetails || "admin@local",
            name: nameClaim?.val || principal.userDetails || "Admin",
            role: principal.userRoles.includes("superadmin") ? "superadmin" : principal.userRoles[0],
            roles: principal.userRoles,
          };
          setUser(derivedUser);
          setIsAuthenticated(true);
        }
      } catch {
        // API not reachable — stay unauthenticated
      } finally {
        // Always runs LAST — prevents PrivateRoute race condition
        setIsLoading(false);
      }
    };
    initAuth();
  }, []);

  // Verify token with backend
  const verifyToken = async (jwt) => {
    try {
      const resp = await axios.get("/api/auth/verify", {
        headers: { Authorization: `Bearer ${jwt}` },
      });
      return resp.data?.valid === true;
    } catch {
      return false;
    }
  };

  // Login
  const login = useCallback(async (email, password) => {
    try {
      const resp = await axios.post("/api/auth/login", { email, password });
      const { token: jwt, user: userData } = resp.data;

      localStorage.setItem("cipp_token", jwt);
      localStorage.setItem("cipp_user", JSON.stringify(userData));

      setToken(jwt);
      setUser(userData);
      setIsAuthenticated(true);
      return { success: true };
    } catch (err) {
      const message = err.response?.data?.error || "Login failed";
      return { success: false, error: message };
    }
  }, []);

  // Register (first user becomes admin)
  const register = useCallback(async (email, password, name) => {
    try {
      const resp = await axios.post("/api/auth/register", { email, password, name });
      const { token: jwt, user: userData } = resp.data;

      localStorage.setItem("cipp_token", jwt);
      localStorage.setItem("cipp_user", JSON.stringify(userData));

      setToken(jwt);
      setUser(userData);
      setIsAuthenticated(true);
      return { success: true };
    } catch (err) {
      const message = err.response?.data?.error || "Registration failed";
      return { success: false, error: message };
    }
  }, []);

  // Logout
  const logout = useCallback(() => {
    localStorage.removeItem("cipp_token");
    localStorage.removeItem("cipp_user");
    setToken(null);
    setUser(null);
    setIsAuthenticated(false);
  }, []);

  // Get token for API calls
  const getToken = useCallback(() => {
    return token;
  }, [token]);

  const value = {
    isAuthenticated,
    isLoading,
    user,
    token,
    login,
    register,
    logout,
    getToken,
  };

  return (
    <LocalAuthContext.Provider value={value}>
      {children}
    </LocalAuthContext.Provider>
  );
}

export function useLocalAuth() {
  const context = useContext(LocalAuthContext);
  if (!context) {
    throw new Error("useLocalAuth must be used within LocalAuthProvider");
  }
  return context;
}

export default LocalAuthContext;
