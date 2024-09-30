// Copyright 2024 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Michael Rogenmoser <michaero@iis.ee.ethz.ch>

package relobi_pkg;

  let max(a,b) = (a > b) ? a : b;

  function automatic int unsigned relobi_a_other_width(obi_pkg::obi_cfg_t Cfg);

    relobi_a_other_width =     1                   /* we */ +
                               Cfg.DataWidth/8     /* be */ +
                               Cfg.IdWidth         /* aid */ +
/* a_optional_t */    max(1, ((Cfg.OptionalCfg.UseAtop    ? 6 : 0) +
                              (Cfg.OptionalCfg.UseMemtype ? 2 : 0) +
                              (Cfg.OptionalCfg.UseProt    ? 3 : 0) +
                              (Cfg.OptionalCfg.UseDbg     ? 1 : 0) +
                               Cfg.OptionalCfg.AUserWidth +
                               Cfg.OptionalCfg.WUserWidth +
                               Cfg.OptionalCfg.MidWidth +
                               Cfg.OptionalCfg.AChkWidth           ));

  endfunction

  function automatic int unsigned relobi_a_other_ecc_width(obi_pkg::obi_cfg_t Cfg);

    relobi_a_other_ecc_width = hsiao_ecc_pkg::min_ecc(relobi_a_other_width(Cfg));

  endfunction

  function automatic int unsigned relobi_r_other_width(obi_pkg::obi_cfg_t Cfg);

    relobi_r_other_width =     1                   /* err */ +
                               Cfg.IdWidth         /* rid */ +
/* a_optional_t */    max(1, ((Cfg.OptionalCfg.UseAtop    ? 1 : 0) +
                               Cfg.OptionalCfg.RUserWidth +
                               Cfg.OptionalCfg.RChkWidth           ));

  endfunction

  function automatic int unsigned relobi_r_other_ecc_width(obi_pkg::obi_cfg_t Cfg);

    relobi_r_other_ecc_width = hsiao_ecc_pkg::min_ecc(relobi_r_other_width(Cfg));

  endfunction

endpackage