/**
 * Login Page for CIPP Local Authentication
 * 
 * Replaces SWA's /.auth/login/aad with a simple email/password form.
 * Also handles first-time registration (first user becomes admin).
 */

import { useState } from "react";
import { useRouter } from "next/router";
import {
  Box,
  Button,
  Card,
  CardContent,
  Container,
  Divider,
  Stack,
  Tab,
  Tabs,
  TextField,
  Typography,
  Alert,
} from "@mui/material";
import { useLocalAuth } from "../contexts/local-auth-context";

export default function LoginPage() {
  const [tab, setTab] = useState(0);
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [name, setName] = useState("");
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);
  const { login, register } = useLocalAuth();
  const router = useRouter();

  const handleLogin = async (e) => {
    e.preventDefault();
    setError("");
    setLoading(true);
    const result = await login(email, password);
    if (result.success) {
      router.push("/");
    } else {
      setError(result.error);
    }
    setLoading(false);
  };

  const handleRegister = async (e) => {
    e.preventDefault();
    setError("");
    setLoading(true);
    const result = await register(email, password, name);
    if (result.success) {
      router.push("/");
    } else {
      setError(result.error);
    }
    setLoading(false);
  };

  return (
    <Box
      sx={{
        backgroundColor: "background.default",
        minHeight: "100vh",
        display: "flex",
        alignItems: "center",
      }}
    >
      <Container maxWidth="sm">
        <Card>
          <CardContent sx={{ p: 4 }}>
            <Typography variant="h4" align="center" gutterBottom>
              M365 MTM
            </Typography>
            <Typography variant="body2" align="center" color="text.secondary" sx={{ mb: 3 }}>
              Microsoft 365 Multi Tenant Management
            </Typography>

            <Tabs value={tab} onChange={(_, v) => setTab(v)} centered sx={{ mb: 3 }}>
              <Tab label="Login" />
              <Tab label="Register" />
            </Tabs>

            {error && (
              <Alert severity="error" sx={{ mb: 2 }}>
                {error}
              </Alert>
            )}

            {tab === 0 && (
              <form onSubmit={handleLogin}>
                <Stack spacing={2}>
                  <TextField
                    label="Email"
                    type="email"
                    value={email}
                    onChange={(e) => setEmail(e.target.value)}
                    required
                    fullWidth
                    autoFocus
                  />
                  <TextField
                    label="Password"
                    type="password"
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    required
                    fullWidth
                  />
                  <Button
                    type="submit"
                    variant="contained"
                    size="large"
                    fullWidth
                    disabled={loading}
                  >
                    {loading ? "Signing in..." : "Sign In"}
                  </Button>
                </Stack>
              </form>
            )}

            {tab === 1 && (
              <form onSubmit={handleRegister}>
                <Stack spacing={2}>
                  <Alert severity="info">
                    First registered user automatically becomes admin.
                  </Alert>
                  <TextField
                    label="Name"
                    value={name}
                    onChange={(e) => setName(e.target.value)}
                    required
                    fullWidth
                  />
                  <TextField
                    label="Email"
                    type="email"
                    value={email}
                    onChange={(e) => setEmail(e.target.value)}
                    required
                    fullWidth
                  />
                  <TextField
                    label="Password"
                    type="password"
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    required
                    fullWidth
                    inputProps={{ minLength: 8 }}
                    helperText="Minimum 8 characters"
                  />
                  <Button
                    type="submit"
                    variant="contained"
                    size="large"
                    fullWidth
                    disabled={loading}
                  >
                    {loading ? "Creating account..." : "Create Account"}
                  </Button>
                </Stack>
              </form>
            )}
          </CardContent>
        </Card>
      </Container>
    </Box>
  );
}
