import { Box, Container, Stack } from "@mui/material";
import { Grid } from "@mui/system";
import Head from "next/head";
import { CippImageCard } from "../components/CippCards/CippImageCard";
import { ApiGetCall } from "../api/ApiCall";
import { useMemo } from "react";

const Page = () => {
  const orgData = ApiGetCall({
    url: "/api/me",
    queryKey: "authmecipp",
  });

  const swaStatus = ApiGetCall({
    url: "/.auth/me",
    queryKey: "authmeswa",
    staleTime: 120000,
    refetchOnWindowFocus: true,
  });

  const blockedRoles = ["anonymous", "authenticated"];
  // Use useMemo to derive userRoles directly
  const userRoles = useMemo(() => {
    if (orgData.isSuccess && orgData.data?.clientPrincipal?.userRoles) {
      return orgData.data.clientPrincipal.userRoles.filter((role) => !blockedRoles.includes(role));
    }
    return [];
  }, [orgData.isSuccess, orgData.data?.clientPrincipal?.userRoles]);

  // Determine link target — use /login for local auth instead of Azure AD
  const isLoggedIn = swaStatus?.data?.clientPrincipal !== null && userRoles.length > 0;
  const linkText = isLoggedIn ? "Return to Home" : "Login";
  const link = isLoggedIn ? "/" : "/login";

  return (
    <>
      <Head>
        <title>401 - Access Denied</title>
      </Head>
      <Box
        sx={{
          flexGrow: 1,
          py: 4,
          height: "100vh",
        }}
      >
        <Container maxWidth={false}>
          <Stack spacing={6} sx={{ height: "100%" }}>
            <Grid
              container
              spacing={3}
              justifyContent="center"
              alignItems="center"
              sx={{ height: "100%" }}
            >
              <Grid size={{ md: 6, xs: 12 }}>
                {(orgData.isSuccess || swaStatus.isSuccess) && Array.isArray(userRoles) && (
                  <CippImageCard
                    isFetching={false}
                    imageUrl="/assets/illustrations/undraw_online_test_re_kyfx.svg"
                    text={
                      orgData?.data?.message ||
                      "You're not allowed to be here, or are logged in under the wrong account."
                    }
                    title="Access Denied"
                    linkText={linkText}
                    link={link}
                  />
                )}
              </Grid>
            </Grid>
          </Stack>
        </Container>
      </Box>
    </>
  );
};

export default Page;
