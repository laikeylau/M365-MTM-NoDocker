import { createContext, useCallback, useContext, useMemo, useState } from "react";
import PropTypes from "prop-types";

const ToastContext = createContext({
  toasts: [],
  showToast: () => {},
  closeToast: () => {},
  resetToast: () => {},
});

export const ToastProvider = ({ children }) => {
  const [toasts, setToasts] = useState([]);
  const [currentIndex, setCurrentIndex] = useState(0);

  const showToast = useCallback(
    ({ message, title, toastError }) => {
      const index = currentIndex + 1;
      setCurrentIndex(index);
      setToasts((prev) => [
        ...prev,
        { message, title, date: Date.now(), toastError, index },
      ]);
      return index;
    },
    [currentIndex],
  );

  const closeToast = useCallback(({ index }) => {
    setToasts((prev) => prev.filter((el) => el.index !== index));
  }, []);

  const resetToast = useCallback(() => {
    setToasts([]);
  }, []);

  const value = useMemo(
    () => ({ toasts, showToast, closeToast, resetToast }),
    [toasts, showToast, closeToast, resetToast],
  );

  return <ToastContext.Provider value={value}>{children}</ToastContext.Provider>;
};

ToastProvider.propTypes = { children: PropTypes.node };

export const useToast = () => useContext(ToastContext);
