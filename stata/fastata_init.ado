*! version 0.1.1  Leo Liu  17oct2026
*! fastata_init: run at startup by the lines fastata enable writes into profile.do. Turns fastata
*! on for the session, rebuilding the runtime directory first when the installed files changed;
*! does nothing after fastata disable. Prints nothing; profile.do runs it under capture, so a
*! failure leaves Stata as it would be without fastata.
program fastata_init
	version 16
	quietly fastata on, init
end
