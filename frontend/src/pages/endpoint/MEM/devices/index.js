import { Layout as DashboardLayout } from "../../../../layouts/index.js";
import { CippTablePage } from "../../../../components/CippComponents/CippTablePage.jsx";
import { CippApiDialog } from "../../../../components/CippComponents/CippApiDialog.jsx";
import { useSettings } from "../../../../hooks/use-settings";
import { useDialog } from "../../../../hooks/use-dialog.js";
import { useCippDeviceActions } from "../../../../components/CippComponents/CippDeviceActions.jsx";
import { Sync } from "@mui/icons-material";
import { Box, Button } from "@mui/material";

const Page = () => {
  const pageTitle = "Devices";
  const tenantFilter = useSettings().currentTenant;
  const depSyncDialog = useDialog();

  const actions = useCippDeviceActions();

  const offCanvas = {
    extendedInfoFields: ["deviceName", "userPrincipalName"],
    actions: actions,
  };

  const simpleColumns = [
    "deviceName",
    "userPrincipalName",
    "complianceState",
    "manufacturer",
    "model",
    "operatingSystem",
    "osVersion",
    "enrolledDateTime",
    "managedDeviceOwnerType",
    "deviceEnrollmentType",
    "joinType",
  ];

  return (
    <>
      <CippTablePage
        title={pageTitle}
        apiUrl="/api/ListGraphRequest"
        apiData={{
          Endpoint: "deviceManagement/managedDevices",
        }}
        apiDataKey="Results"
        actions={actions}
        queryKey={`MEMDevices-${tenantFilter}`}
        offCanvas={offCanvas}
        simpleColumns={simpleColumns}
        cardButton={
          <Box sx={{ display: "flex", gap: 1 }}>
            <Button onClick={depSyncDialog.handleOpen} startIcon={<Sync />}>
              Sync DEP
            </Button>
          </Box>
        }
      />
      <CippApiDialog
        title="Sync DEP Tokens"
        createDialog={depSyncDialog}
        api={{
          type: "POST",
          url: "/api/ExecSyncDEP",
          data: {},
          confirmText: `Are you sure you want to sync Apple Device Enrollment Program (DEP) tokens? This will sync all DEP tokens for ${tenantFilter}. This may take several minutes to complete in the background, and can only be done every 15 minutes.`,
        }}
      />
    </>
  );
};

Page.getLayout = (page) => <DashboardLayout>{page}</DashboardLayout>;

export default Page;
