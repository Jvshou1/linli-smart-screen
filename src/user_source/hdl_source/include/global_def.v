


`define   DATA_WIDTH                        32
`define   ADDR_WIDTH                        21
`define   DM_WIDTH                          4

`define   ROW_WIDTH                        11
`define   BA_WIDTH                        2

`define	  SDR_CLK_PERIOD				(1000000000/100000000)
// Refresh all rows within 32 ms to retain margin during continuous video reads.
`define   SELF_REFRESH_INTERVAL			(32000000/`SDR_CLK_PERIOD/(2**(`ROW_WIDTH)))

