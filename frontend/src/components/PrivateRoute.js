import { useContext } from "react";
import { LocalAuthContext } from "../contexts/local-auth-context";
import UnauthenticatedPage from "../pages/unauthenticated.js";
import LoadingPage from "../pages/loading.js";

// Routes that don't require authentication
const PUBLIC_PATHS = ["/login", "/unauthenticated", "/license"];

export const PrivateRoute = ({ children, routeType }) => {
  const context = useContext(LocalAuthContext);

  // During SSR/static generation, context may be undefined
  if (!context) {
    return children;
  }

  const { user, isAuthenticated, isLoading } = context;

  // Allow public paths without authentication
  if (typeof window !== "undefined") {
    const currentPath = window.location.pathname;
    if (PUBLIC_PATHS.some((p) => currentPath.startsWith(p))) {
      return children;
    }
  }

  if (isLoading) {
    return <LoadingPage />;
  }

  if (!isAuthenticated || !user) {
    return <UnauthenticatedPage />;
  }

  // For admin routes, check if user has admin role
  if (routeType === "admin" && user.role !== "admin" && user.role !== "superadmin") {
    return <UnauthenticatedPage />;
  }

  return children;
};
