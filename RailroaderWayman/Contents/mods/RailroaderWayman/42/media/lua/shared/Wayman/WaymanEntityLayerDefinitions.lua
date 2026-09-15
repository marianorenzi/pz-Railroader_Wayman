RailroaderWaymanEntityLayers = RailroaderWaymanEntityLayers or {}

-- Coordinates use rows[y + 1][x + 1]. `false` leaves the square unchanged.
-- Each entry in `layers` adds another visual IsoObject over the same grid.
RailroaderWaymanEntityLayers.Definitions = {
    Degree45LeftTurnSegment = {
        N = {
            layers = {
                {
                    rows = {
                        -- { "industry_railroad_02_42", "industry_railroad_02_41", "industry_railroad_02_39", false, false, false },
                        -- { "industry_railroad_02_40", "industry_railroad_02_38", "industry_railroad_02_36", "industry_railroad_02_34", false, false },
                        -- { "industry_railroad_02_37", "industry_railroad_02_35", "industry_railroad_02_33", "industry_railroad_01_19", "industry_railroad_01_20", false },
                        -- { false, "industry_railroad_02_32", "industry_railroad_01_17", "industry_railroad_01_18", "industry_railroad_01_19", "industry_railroad_01_20" },
                        { false, false, false, false, false, false },
                        { false, false, false, false, false, false },
                        { false, false, false, "industry_railroad_01_19", "industry_railroad_01_20", false },
                        { false, false, "industry_railroad_01_17", "industry_railroad_01_18", "industry_railroad_01_19", "industry_railroad_01_20" },
                    },
                },
            },
        },
        S = {
            layers = {
                {
                    rows = {
                        -- { "industry_railroad_01_16", "industry_railroad_01_17", "industry_railroad_01_18", "industry_railroad_01_19", "industry_railroad_02_2", false, false },
                        -- { false, "industry_railroad_01_16", "industry_railroad_01_17", "industry_railroad_02_1", "industry_railroad_02_4", "industry_railroad_02_7", false },
                        -- { false, false, "industry_railroad_02_0", "industry_railroad_02_3", "industry_railroad_02_6", "industry_railroad_02_9", "industry_railroad_02_11" },
                        -- { false, false, false, "industry_railroad_02_5", "industry_railroad_02_8", "industry_railroad_02_10", "industry_railroad_02_12" },
                        { "industry_railroad_01_16", "industry_railroad_01_17", "industry_railroad_01_18", "industry_railroad_01_19", false, false, false },
                        { false, "industry_railroad_01_16", "industry_railroad_01_17", false, false, false, false },
                        { false, false, false, false, false, false, false },
                        { false, false, false, false, false, false, false },
                    },
                },
            },
        },
        E = {
            layers = {
                {
                    rows = {
                        -- { "industry_railroad_01_58", "industry_railroad_01_62", "industry_railroad_01_63" },
                        -- { "industry_railroad_01_56", "industry_railroad_01_59", "industry_railroad_01_61" },
                        -- { "industry_railroad_01_11", "industry_railroad_01_47", "industry_railroad_01_60" },
                        -- { "industry_railroad_01_8", "industry_railroad_01_9", false },
                        -- { "industry_railroad_01_9", false, false },
                        { false, false, false },
                        { false, false, false },
                        { "industry_railroad_01_11", false, false },
                        { "industry_railroad_01_8", "industry_railroad_01_9", false },
                        { "industry_railroad_01_9", false, false },
                    },
                },
            },
        },
        W = {
            layers = {
                {
                    rows = {
                        -- { "industry_railroad_01_34", "industry_railroad_01_38", "industry_railroad_01_11", "industry_railroad_01_8", "industry_railroad_01_9" },
                        -- { "industry_railroad_01_32", "industry_railroad_01_35", "industry_railroad_01_39", "industry_railroad_01_9", false },
                        -- { "industry_railroad_01_40", "industry_railroad_01_33", "industry_railroad_01_36", false, false },
                        { false, false, "industry_railroad_01_11", "industry_railroad_01_8", "industry_railroad_01_9" },
                        { false, false, false, "industry_railroad_01_9", false },
                        { false, false, false, false, false },
                    },
                },
            },
        },
    },
    Degree45RightTurnSegment = {
        N = {
            layers = {
                {
                    rows = {
                        -- { false, false, "industry_railroad_01_26", "industry_railroad_01_29", "industry_railroad_01_31", "industry_railroad_01_41" },
                        -- { false, "industry_railroad_01_12", "industry_railroad_01_13", "industry_railroad_01_25", "industry_railroad_01_28", "industry_railroad_01_30" },
                        -- { "industry_railroad_01_12", "industry_railroad_01_13", "industry_railroad_01_10", "industry_railroad_01_11", "industry_railroad_01_8", "industry_railroad_01_27" },
                        { false, false, false, false, false, false },
                        { false, "industry_railroad_01_12", "industry_railroad_01_13", false, false, false },
                        { "industry_railroad_01_12", "industry_railroad_01_13", "industry_railroad_01_10", "industry_railroad_01_11", "industry_railroad_01_8", false },
                    },
                },
            },
        },
        S = {
            layers = {
                {
                    rows = {
                        -- { "industry_railroad_01_54", "industry_railroad_01_13", "industry_railroad_01_10", "industry_railroad_01_11", "industry_railroad_01_8", "industry_railroad_01_9" },
                        -- { "industry_railroad_01_53", "industry_railroad_01_55", "industry_railroad_01_11", "industry_railroad_01_8", "industry_railroad_01_9", false },
                        -- { "industry_railroad_01_49", "industry_railroad_01_52", "industry_railroad_01_46", "industry_railroad_01_9", false, false },
                        -- { "industry_railroad_01_48", "industry_railroad_01_50", "industry_railroad_01_51", false, false, false },
                        { false, "industry_railroad_01_13", "industry_railroad_01_10", "industry_railroad_01_11", "industry_railroad_01_8", "industry_railroad_01_9" },
                        { false, false, "industry_railroad_01_11", "industry_railroad_01_8", "industry_railroad_01_9", false },
                        { false, false, false, "industry_railroad_01_9", false, false },
                        { false, false, false, false, false, false },
                    },
                },
            },
        },
        E = {
            layers = {
                {
                    rows = {
                        -- { "industry_railroad_01_16", "industry_railroad_01_17", "industry_railroad_02_17", "industry_railroad_02_20", "industry_railroad_02_23" },
                        -- { false, "industry_railroad_02_16", "industry_railroad_02_19", "industry_railroad_02_22", "industry_railroad_02_25" },
                        -- { false, false, "industry_railroad_02_21", "industry_railroad_02_24", "industry_railroad_02_26" },
                        -- { false, false, false, "industry_railroad_02_28", "industry_railroad_02_27" },
                        { "industry_railroad_01_16", "industry_railroad_01_17", false, false, false, false },
                        { false, false, false, false, false, false },
                        { false, false, false, false, false, false },
                        { false, false, false, false, false, false },
                    },
                },
            },
        },
        W = {
            layers = {
                {
                    rows = {
                        -- { "industry_railroad_02_47", "industry_railroad_02_46", false, false, false, false },
                        -- { "industry_railroad_02_45", "industry_railroad_02_54", "industry_railroad_02_52", "industry_railroad_02_50", false, false },
                        -- { "industry_railroad_02_53", "industry_railroad_02_51", "industry_railroad_02_49", "industry_railroad_01_19", "industry_railroad_01_20", false },
                        -- { false, "industry_railroad_02_48", "industry_railroad_01_17", "industry_railroad_01_18", "industry_railroad_01_19", "industry_railroad_01_20" },
                        { false, false, false, false, false, false },
                        { false, false, false, false, false, false },
                        { false, false, false, "industry_railroad_01_19", "industry_railroad_01_20", false },
                        { false, false, "industry_railroad_01_17", "industry_railroad_01_18", "industry_railroad_01_19", "industry_railroad_01_20" },
                    },
                },
            },
        },
    },
}
