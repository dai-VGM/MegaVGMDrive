module emu;
    localparam CONF_STR = {"MegaVGMDrive;;"};
    hps_io hps_io (.status_in(status_in), .status_set(status_set));
    megavgm_playlist_status_export playlist_status_export (
        .status_in(status_in), .status_set(status_set)
    );
endmodule
