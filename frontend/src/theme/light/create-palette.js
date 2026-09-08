import { common } from '@mui/material/colors';
import { alpha } from '@mui/material/styles';
import { error, info, neutral, success, warning } from '../colors';
import { getPrimary } from '../utils';

export const createPalette = (config) => {
  const { colorPreset, contrast } = config;

  return {
    action: {
      active: neutral[400],
      disabled: alpha(neutral[900], 0.38),
      disabledBackground: alpha(neutral[900], 0.12),
      focus: alpha(neutral[900], 0.16),
      hover: alpha(neutral[900], 0.04),
      selected: alpha(neutral[900], 0.12)
    },
    background: {
      default: contrast === 'high' ? '#F1F5F9' : '#F8FAFC',
      paper: '#FFFFFF'
    },
    divider: alpha(neutral[400], 0.2),
    error,
    info,
    mode: 'light',
    neutral,
    primary: getPrimary(colorPreset),
    success,
    text: {
      primary: neutral[900],
      secondary: neutral[500],
      disabled: alpha(neutral[900], 0.38)
    },
    warning
  };
};
