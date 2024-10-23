// Copyright 2024 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Michael Rogenmoser <michaero@iis.ee.ethz.ch>

package relobi_pkg;
  // `let` is not supported by VCS, change it to a function
  function automatic integer unsigned sigwidth (input integer unsigned width);
    return (width != 32'd0) ? unsigned'(width) : 32'd1;
  endfunction

  // Even though the functionality is not used, one bit field will still be created
  // Thus it would be better to count the signal width
  function automatic int unsigned relobi_a_other_width(obi_pkg::obi_cfg_t Cfg);

    relobi_a_other_width =     1                   /* we */ +
                               Cfg.DataWidth/8     /* be */ +
                               Cfg.IdWidth         /* aid */ +
/* a_optional_t */   sigwidth((Cfg.OptionalCfg.UseAtop    ? 6 : 0) +
                              (Cfg.OptionalCfg.UseMemtype ? 2 : 0) +
                              (Cfg.OptionalCfg.UseProt    ? 3 : 0) +
                              (Cfg.OptionalCfg.UseDbg     ? 1 : 0) +
                              (Cfg.OptionalCfg.AUserWidth) +
                              (Cfg.OptionalCfg.WUserWidth) +
                              (Cfg.OptionalCfg.MidWidth  ) +
                              (Cfg.OptionalCfg.AChkWidth ));

  endfunction

  function automatic int unsigned relobi_a_other_ecc_width(obi_pkg::obi_cfg_t Cfg);

    relobi_a_other_ecc_width = hsiao_ecc_pkg::min_ecc(relobi_a_other_width(Cfg));

  endfunction

  function automatic int unsigned relobi_r_other_width(obi_pkg::obi_cfg_t Cfg);
    // Error is not implemented yet, take it out from ecc for testing
    relobi_r_other_width =     Cfg.IdWidth         /* rid */ +
                               // 1                   /* err */ +
/* a_optional_t */   sigwidth((Cfg.OptionalCfg.UseAtop    ? 1 : 0) +
                              (Cfg.OptionalCfg.RUserWidth) +
                              (Cfg.OptionalCfg.RChkWidth ));

  endfunction

  function automatic int unsigned relobi_r_other_ecc_width(obi_pkg::obi_cfg_t Cfg);

    relobi_r_other_ecc_width = hsiao_ecc_pkg::min_ecc(relobi_r_other_width(Cfg));

  endfunction

endpackage