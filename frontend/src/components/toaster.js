import { CloseSharp } from "@mui/icons-material";
import { Alert, IconButton, Snackbar } from "@mui/material";
import { useToast } from "../contexts/toast-context";

const Toasts = () => {
  const { toasts, closeToast } = useToast();

  return (
    <>
      {[
        toasts.map((toast) => (
          <Snackbar
            sx={{ maxWidth: "20%" }}
            anchorOrigin={{ vertical: "top", horizontal: "right" }}
            key={toast.index}
            open={true}
            autoHideDuration={6000}
            onClose={() => closeToast({ index: toast.index })}
            action={
              <>
                <IconButton
                  size="small"
                  aria-label="close"
                  color="inherit"
                  onClick={() => closeToast({ index: toast.index })}
                >
                  <CloseSharp fontSize="small" />
                </IconButton>
              </>
            }
          >
            <Alert
              onClose={() => closeToast({ index: toast.index })}
              severity="error"
              variant="filled"
              sx={{ width: "100%" }}
            >
              {toast.toastError.status} - {toast.message}
            </Alert>
          </Snackbar>
        )),
      ]}
    </>
  );
};

export default Toasts;
