#define CHOICE_X_START          0
#define CHOICE_Y_START          0

#include "ui_mp/menustyle.inc"
#include "ui/choices_setup_common.menu"
 
#define ORIGIN_STATUS           390 64
#define MENU_FONT_COLOR2        1 1 1 0.5
#define OPENMENUONDVAR(dvar,dvarArg,menuArg) \
	if ( dvarString( dvar ) == dvarArg ) { open menuArg }


    menuDef {
        name            CAC_MENU_NAME
        rect            0 0 640 480
        focuscolor      COLOR_FOCUSED
        style           WINDOW_STYLE_EMPTY
        blurWorld       3.0

        onEsc {
            scriptMenuResponse "back";
        }
		
		#include "ui_mp/emzui/ingamebg.inc"

		itemDef
		{
			rect 48 30 0 0
			text			"Class"
			textfont		UI_FONT_NORMAL
			forecolor       COLOR_TITLE
			textscale		TEXTSIZE_TITLE
			textStyle 		6
			visible			1
			decoration
		}
		
        #define BACK_OPEN ;
		#include "ui_mp/navcontrols.inc"
        
        // PRIMARY WEAPON BUTTON =============================================================
        // ESL-MOD: demolitions stripped, so the popup only opens for assault,
        // specops and sniper.  Do not put comments inside this macro - a line
        // that does not end with a backslash terminates it and breaks the file.
        #define CAC_SETUP_ACTION1 \
            play "mouse_click"; \
   OPENMENUONDVAR(loadout_class,assault,ocd_popup_cac_assault)\
			OPENMENUONDVAR(loadout_class,specops,ocd_popup_cac_specops)\
			OPENMENUONDVAR(loadout_class,sniper,ocd_popup_cac_sniper)

        CHOICE_HIGHLIGHT( 1, 0 )        
        CHOICE_BUTTON_NOHI( 1, "1. Primary Weapon", CAC_SETUP_ACTION1 )
        execKey "1" { CAC_SETUP_ACTION1; }

        #define CAC_SETUP_ACTION_ATTACHMENT \
            play "mouse_click"; \
   OPENMENUONDVAR(loadout_class,assault,ocd_attachment_popup_assault) \
   if( dvarString( loadout_primary ) != "ak74u") { OPENMENUONDVAR(loadout_class,specops,ocd_attachment_popup_specops) }\
   OPENMENUONDVAR(loadout_class,sniper,ocd_attachment_popup_sniper)

        CHOICE_HIGHLIGHT( 2, 1 )
		// ESL-MOD: snipers get their attachments too, except the M40A3 which
		// takes none at all in this game.  The AK-74u exclusion is a ProMod rule
		// - the game itself would allow attachments on it.
		CHOICE_BUTTON_VIS_NOHI( 2, "2. Primary Attachment", CAC_SETUP_ACTION_ATTACHMENT, when( dvarString( loadout_primary ) != "ak74u" && dvarString( loadout_primary ) != "m40a3" ) )
		      CHOICE_DBUTTON_VIS_NOHI( 2, "2. Primary Attachment", when( dvarString( loadout_primary ) == "ak74u" || dvarString( loadout_primary ) == "m40a3" ) )
        execKey "2" { CAC_SETUP_ACTION_ATTACHMENT; }

        // SECONDARY WEAPON/SIDE ARM BUTTON =============================================================
        #define CAC_SETUP_ACTION2 \
            play "mouse_click"; \
            open "ocd_popup_cac_secondary";

        CHOICE_BUTTON_BG( 3, 0 )
        CHOICE_HIGHLIGHT( 3, 0 )        
        CHOICE_BUTTON_NOHI( 3, "3. Side Arm", CAC_SETUP_ACTION2 )
        execKey "3" { CAC_SETUP_ACTION2; }
        
        // LETHAL and TACTICAL BUTTONS =======================================================
        // ESL-MOD: the lethal (equipment) and the tactical (special grenade) are two
        // separate slots, so they get an entry each instead of one list of four.
        #define CAC_SETUP_ACTION_LETHAL \
            play "mouse_click"; \
            open "ocd_popup_cac_lethal";

        CHOICE_HIGHLIGHT( 4, 0 )
        CHOICE_BUTTON_NOHI( 4, "4. Lethal", CAC_SETUP_ACTION_LETHAL )
        execKey "4" { CAC_SETUP_ACTION_LETHAL; }

        #define CAC_SETUP_ACTION_TACTICAL \
            play "mouse_click"; \
            open "ocd_popup_cac_extra";

        CHOICE_HIGHLIGHT( 5, 0 )
        CHOICE_BUTTON_NOHI( 5, "5. Tactical", CAC_SETUP_ACTION_TACTICAL )
        execKey "5" { CAC_SETUP_ACTION_TACTICAL; }
		
        #define CAC_SETUP_ACTION4 \
            play "mouse_click"; \
            if ( dvarString( loadout_primary ) != "ranger" && dvarString( loadout_primary ) != "model1887"  && dvarString( loadout_primary ) != "ak74u" && dvarString( loadout_primary ) != "m40a3" ) { open "ocd_popup_cac_camo"; }
		
        CHOICE_HIGHLIGHT( 6, 0 )
  CHOICE_BUTTON_VIS_NOHI( 6, "6. Camo", CAC_SETUP_ACTION4, when( dvarString( loadout_primary ) != "ranger" && dvarString( loadout_primary ) != "model1887"  && dvarString( loadout_primary ) != "ak74u" && dvarString( loadout_primary ) != "m40a3" ) )
  CHOICE_DBUTTON_VIS_NOHI( 6, "6. Camo", when( dvarString( loadout_primary ) == "ranger" || dvarString( loadout_primary ) == "model1887" ||  dvarString( loadout_primary ) == "ak74u" || dvarString( loadout_primary ) == "m40a3") )
        execKey "6" { CAC_SETUP_ACTION4; }
		
        #define CAC_SETUP_ACTIONGO \        
            play "mouse_click"; \
            scriptMenuResponse "start";

        CHOICE_HIGHLIGHT( 7, 0 )
  CHOICE_BUTTON_NOHI( 7, "7. Start!", CAC_SETUP_ACTIONGO )
        execKey "7" { CAC_SETUP_ACTIONGO; }

        #define STAT_CAC_PRIMARY                tableLookup("mp/statstable.csv", 4, dvarString( loadout_primary ), 0)
        #define STAT_CAC_PRIMARY_ATTACHMENT     tableLookup("mp/attachmentTable.csv", 4, dvarString( loadout_primary_attachment ), 9)
        #define STAT_CAC_SECONDARY              tableLookup("mp/statstable.csv", 4, dvarString( loadout_secondary ), 0)
        #define STAT_CAC_SECONDARY_ATTACHMENT   tableLookup("mp/attachmentTable.csv", 4, dvarString( loadout_secondary_attachment ), 9)
        #define STAT_CAC_SPECIAL_GRENADE        tableLookup("mp/statstable.csv", 4, dvarString( loadout_grenade ), 0)
        #define STAT_CAC_CAMO                 	tablelookup("mp/camotable.csv",1,dvarString( loadout_camo ),4)
        // =====================================================================
        //  ESL-MOD: weapon stats footer
        //
        //  Two blocks under the buttons, one for the primary and one for the
        //  secondary, in plain numbers - no stat bars - so somebody who does not
        //  know the ESL rule set yet can see what a gun actually does before
        //  taking it into a round:
        //
        //      Primary     DMG 40-30  Head 1.6x
        //                  Range 51 m  RPM 706
        //
        //  The cells come from mp/esl_weaponstats.csv, which tools\build.ps1
        //  generates from the weapon files *after* the ESL tweaks, so they carry
        //  what the match really uses.  The stock mp/statstable.csv the loadout
        //  panel draws could not be reused: it still describes the un-rebalanced
        //  weapons and its columns hold the 0-100 bar values.
        //
        //  Two rules decide this layout, and both cost a round of "it looks
        //  garbled" to learn:
        //
        //  1. A table cell may not hold a '|' - the engine's table parser cuts a
        //     cell at one - so the lines are worded with spaces instead.  Not one
        //     cell in the game's own 77 tables carries a '|' or a ':' either.  The
        //     parser does accept spaces and hyphens inside a cell (1155 and 414
        //     cells of those tables use them), which is what lets the wording sit
        //     in the cell at all.
        //  2. A text item WRAPS at the width of its box and draws the rest on the
        //     following line, over whatever is under it.  Every box here is much
        //     wider than the text that lands in it and the text is kept to about
        //     30 characters, which is also why a block is two lines.
        //
        //  The keys are the dvars the editor already maintains, so the numbers
        //  follow whatever the class currently holds.
        // =====================================================================

        #define ESL_STATS_ORIGIN        48 350
        #define ESL_STATS_ALIGN         HORIZONTAL_ALIGN_LEFT VERTICAL_ALIGN_TOP

        //  One item per slot: the slot name, then the single line the server pushes
        //  as a client dvar - esl_stats_primary and esl_stats_secondary, filled by
        //  esl_publishWeaponStats() in _esl.gsc.
        //
        //  Drawing a dvar is what this menu is good at (loadout_primary, the team
        //  names, the grenade counts are all dvars); a table cell is not - see the
        //  note above.  And the text has to be composed somewhere, which only
        //  script can do, so the two ends meet here.
        #define ESL_LABEL( px, py, label ) \
            PREPROC_TEXT_DRAW_ALIGNED_EXP( px py 132 16 ESL_STATS_ALIGN, ESL_STATS_ORIGIN, label, TEXTSIZE_SMALL, 0, 0, ITEM_ALIGN_MIDDLE_LEFT, COLOR_TITLE ) \

        #define ESL_STAT( px, py, statDvar ) \
            PREPROC_TEXT_DRAW_ALIGNED_EXP( px py 440 16 ESL_STATS_ALIGN, ESL_STATS_ORIGIN, dvarString( statDvar ), TEXTSIZE_SMALL, 0, 0, ITEM_ALIGN_MIDDLE_LEFT, CHOICE_TEXTCOLOR ) \

        // ---- primary, then secondary ----
        ESL_LABEL(   0,   0, "Primary" )
        ESL_STAT(  140,   0, esl_stats_primary )

        ESL_LABEL(   0,  24, "Secondary" )
        ESL_STAT(  140,  24, esl_stats_secondary )

        #include "ui_mp/emzui/cac_loadout_ingame.inc"
    }

    // close all 2nd and 3rd layer popups on end action
    #define PREPROC_ATTACH_CLOSEALL \
    close "ocd_popup_cac_primary"; \
    close "ocd_popup_cac_secondary"; \
    close "ocd_popup_cac_assault"; \
    close "ocd_popup_cac_specops"; \
    close "ocd_popup_cac_sniper"; \
    close "ocd_popup_cac_demolitions"; \
    close "popup_cac_template"; \
    close "ocd_attachment_popup_assault"; \
    close "ocd_attachment_popup_specops"; \
	close "ocd_attachment_popup_demolitions"; \
    close "ocd_attachment_popup_pistol"; \
    close "ocd_popup_cac_camo"; \
    close "ocd_attachment_popup_fake";  
    
    // including weapon data
    #include "ui_mp/weaponinfo.menu"
    
#include "ui_mp/popupstyle.inc" 
#include "ui/choices_setup_popmenu.menu"

#undef CHOICE_SIZE_X
#define CHOICE_SIZE_X           216

#undef NEW_X_OFFSET         
#define NEW_X_OFFSET    (0-CHOICE_SIZE_X)

#undef NEW_Y_OFFSET         
#define NEW_Y_OFFSET    (0-2)
#undef CHOICE_Y_START
#define CHOICE_Y_START 1

    // ====================================================================================================
    // primary weapon selection ===========================================================================
    // ====================================================================================================
	#define LOCAL_WEAPON_INFO_WINDOW \
		/* weapon information side frame*/ \
		PREPROC_SHADER_DRAW_ALIGNED( (CHOICE_POPUP_WIDTH-6) -4 280 CHOICE_POPUP_HEIGHT( 9 ) CHOICE_HORIZONTAL_ALIGN CHOICE_VERTICAL_ALIGN, 0 0, "white", CHOICE_POPUP_BORDER_COLOR, 1, 2, CHOICE_POPUP_BORDER_COLOR visible when( 1 ); ) \
		LOADOUT_PLATING_RAW( CHOICE_POPUP_WIDTH 8, -4, -2, 280, (CHOICE_POPUP_HEIGHT( 9 )-4), CHOICE_HORIZONTAL_ALIGN CHOICE_VERTICAL_ALIGN visible when( 1 );, 0, 0 )\
		/* weapon image*/ \
		PREPROC_SHADER_DRAW_ALIGNED( (CHOICE_POPUP_WIDTH+6) 30 256 48 CHOICE_HORIZONTAL_ALIGN CHOICE_VERTICAL_ALIGN, 0 0, "gradient_bottom", 1 1 1 0.3, 0, 2, CHOICE_POPUP_BORDER_COLOR visible when( 1 ); ) \
		PREPROC_SHADER_DRAW_ALIGNED( (CHOICE_POPUP_WIDTH+72) -6 180 90 CHOICE_HORIZONTAL_ALIGN CHOICE_VERTICAL_ALIGN, 0 0, tablelookup("mp/statsTable.csv",4,dvarString("ui_primary_highlighted"),6), 1 1 1 1, 0, 2, CHOICE_POPUP_BORDER_COLOR visible when( 1 ); ) \
		/* weapon title*/\
		PREPROC_TEXT_DRAW_ALIGNED_EXP( (CHOICE_POPUP_WIDTH+10) 58 256 20 CHOICE_HORIZONTAL_ALIGN CHOICE_VERTICAL_ALIGN, 0 0, "@"+tablelookup("mp/statstable.csv",4,dvarString("ui_primary_highlighted"),3), TEXTSIZE_DEFAULT, 0, 0, ITEM_ALIGN_MIDDLE_LEFT, COLOR_TITLE visible when( 1 ); ) \
		/* weapon desc unlocked*/\
		PREPROC_TEXT_DRAW_ALIGNED_EXP( (CHOICE_POPUP_WIDTH+10) 80 256 20 CHOICE_HORIZONTAL_ALIGN CHOICE_VERTICAL_ALIGN, 0 0, "@"+tablelookup("mp/statstable.csv",4,dvarString("ui_primary_highlighted"),7), TEXTSIZE_SMALL, 0, 0, ITEM_ALIGN_MIDDLE_LEFT, CHOICE_TEXTCOLOR visible 1  )\
		
    #define LOCAL_PRIMARY_WEAPON_ACTION( weapRef ) \
        play "mouse_click"; \
        scriptMenuResponse "loadout_primary:"weapRef;\
        setdvar loadout_primary weapRef; \
		setdvar loadout_camo none; \
		close self;\
		scriptMenuResponse "go";
		
	#define WI_FOCUS_ACTION( weaponRef ) \
		exec "set ui_primary_highlighted "weaponRef;

    #define LOCAL_WEAPON_ITEM( itemNum, weaponName, weaponRef )\
        CHOICE_BUTTON_FOCUS_VIS_NOHI( itemNum, "", ;, execnow "set ui_primary_highlighted "weaponRef;, ;, when(!dvarBool( "weap_allow_"weaponRef )); ) \
        CHOICE_DBUTTON_VIS_NOHI( itemNum, weaponName, when(!dvarBool( "weap_allow_"weaponRef )); ) \
        CHOICE_BUTTON_FOCUS_VIS_NOHI( itemNum, weaponName, LOCAL_PRIMARY_WEAPON_ACTION( weaponRef ), \
        WI_FOCUS_ACTION( weaponRef ), ;, when(dvarBool( "weap_allow_"weaponRef )); ) \
        CHOICE_HIGHLIGHT( itemNum, when(dvarBool( "weap_allow_"weaponRef )) ) \
        execKey itemNum { LOCAL_PRIMARY_WEAPON_ACTION( weaponRef ) } \

	#undef  UI_FOCUSFIRST
	#define UI_FOCUSFIRST "ui_primary_highlighted"
	
    // primary weapon items
    //
    // NOTE (ESL-MOD): the M40A3 is back in the sniper popup.  It takes no
    // attachment at all in this game, so the "Primary Attachment" button is
    // disabled for it (see the when() further down), but that is no longer a
    // reason to hide the weapon: what used to make picking it hand out an M4 was
    // that multiplayer loads weapons/mp/m40a3_mp and the mod only shipped the
    // archive's stray "m40a3" file - a singleplayer-style leftover with damage
    // 400 - so the engine had nothing to give.  The mod ships m40a3_mp now
    // (src\weapons\extra, see docs\WEAPONS.md).
    //
    // Do NOT put comments inside this macro - a line that does not end with a
    // backslash terminates it and deletes the menus it defines.
     #define LOCAL_MASTER_WEAPON_GROUP( pos, y_offset )\
    menuDef {\
        IMPROVED_POPUP_SETUP_ONOPEN( "ocd_popup_cac_assault", 9, (CHOICE_X( pos )), (CHOICE_Y( pos )-y_offset), ;, execnow "set "UI_FOCUSFIRST" ak47; set ui_inside_popup assault";, 0 )\
        LOCAL_WEAPON_INFO_WINDOW\
        LOCAL_WEAPON_ITEM( 1, "1. AK-47", "ak47" )\
		LOCAL_WEAPON_ITEM( 2, "2. M16A4", "m16" )\
        LOCAL_WEAPON_ITEM( 3, "3. M4A1", "m4" )\
        LOCAL_WEAPON_ITEM( 4, "4. FAMAS", "famas" )\
        LOCAL_WEAPON_ITEM( 5, "5. SCAR-H", "scar" )\
        LOCAL_WEAPON_ITEM( 6, "6. TAR-21", "tavor" )\
        LOCAL_WEAPON_ITEM( 7, "7. FAL", "fal" )\
		LOCAL_WEAPON_ITEM( 8, "8. ACR", "masada" )\
		LOCAL_WEAPON_ITEM( 9, "9. F2000", "fn2000" )\
    }\
    menuDef {\
        IMPROVED_POPUP_SETUP_ONOPEN( "ocd_popup_cac_specops", 9, (CHOICE_X( pos )), (CHOICE_Y( pos )-y_offset), ;, execnow "set "UI_FOCUSFIRST" mp5k;set ui_inside_popup specops";, 0 )\
        LOCAL_WEAPON_INFO_WINDOW\
        LOCAL_WEAPON_ITEM( 1, "1. MP5K", "mp5k" )\
        LOCAL_WEAPON_ITEM( 2, "2. UMP45", "ump45" )\
        LOCAL_WEAPON_ITEM( 3, "3. Vector", "kriss" )\
  LOCAL_WEAPON_ITEM( 4, "4. Mini-Uzi", "uzi" )\
  LOCAL_WEAPON_ITEM( 5, "5. AK-74u", "ak74u" )\
        LOCAL_WEAPON_ITEM( 6, "6. P90", "p90" )\
    }\
    menuDef {\
        IMPROVED_POPUP_SETUP_ONOPEN( "ocd_popup_cac_demolitions", 9, (CHOICE_X( pos )), (CHOICE_Y( pos )-y_offset), ;, execnow "set "UI_FOCUSFIRST" spas12; set ui_inside_popup demolitions";, 0 )\
        LOCAL_WEAPON_INFO_WINDOW\
        LOCAL_WEAPON_ITEM( 1, "1. SPAS-12", "spas12" )\
		LOCAL_WEAPON_ITEM( 2, "2. M1014", "m1014" )\
		LOCAL_WEAPON_ITEM( 3, "3. Ranger", "ranger" )\
		LOCAL_WEAPON_ITEM( 4, "4. Model 1887", "model1887" )\
    }\
    menuDef {\
        IMPROVED_POPUP_SETUP_ONOPEN( "ocd_popup_cac_sniper", 9, (CHOICE_X( pos )), (CHOICE_Y( pos )-y_offset), ;, execnow "set "UI_FOCUSFIRST" cheytac; set ui_inside_popup sniper";, 0 )\
        LOCAL_WEAPON_INFO_WINDOW\
        LOCAL_WEAPON_ITEM( 1, "1. Intervention", "cheytac" )\
        LOCAL_WEAPON_ITEM( 2, "2. M40A3", "m40a3" )\
    }
    // primary and second primary weapon selection popup menus
    LOCAL_MASTER_WEAPON_GROUP( 1, 57 )
    
    // ====================================================================================================
    // primary and second primary attachment selection ====================================================
    // ====================================================================================================
    // ESL-MOD: sized for three attachment entries (None / FMJ / Extended Mags)
    #define LOCAL_ATTACHMENT_INFO_WINDOW \
        /* attachment information side frame*/ \
        PREPROC_SHADER_DRAW_ALIGNED( (CHOICE_POPUP_WIDTH-6) -4 280 CHOICE_POPUP_HEIGHT( 7 ) CHOICE_HORIZONTAL_ALIGN CHOICE_VERTICAL_ALIGN, 0 0, "white", CHOICE_POPUP_BORDER_COLOR, 1, 2, CHOICE_POPUP_BORDER_COLOR visible when( dvarString(ui_inside_popup) != "camo" ); ) \
        LOADOUT_PLATING_RAW( CHOICE_POPUP_WIDTH 8, -4, -2, 280, (CHOICE_POPUP_HEIGHT( 7 )-4), CHOICE_HORIZONTAL_ALIGN CHOICE_VERTICAL_ALIGN visible when( dvarString(ui_inside_popup) != "camo" );, 0, 0 ) \
        /* attachment image*/ \
        PREPROC_SHADER_DRAW_ALIGNED( (CHOICE_POPUP_WIDTH+6) 30 256 48 CHOICE_HORIZONTAL_ALIGN CHOICE_VERTICAL_ALIGN, 0 0, "gradient_bottom", 1 1 1 0.3, 0, 2, CHOICE_POPUP_BORDER_COLOR visible when( dvarString(ui_inside_popup) != "camo" ); ) \
        PREPROC_SHADER_DRAW_ALIGNED( (CHOICE_POPUP_WIDTH+182) 6 64 64 CHOICE_HORIZONTAL_ALIGN CHOICE_VERTICAL_ALIGN, 0 0, tablelookup("mp/attachmentTable.csv",4,dvarString(ui_attachment_highlighted),6), 1 1 1 1, 0, 2, CHOICE_POPUP_BORDER_COLOR visible when( dvarString(ui_inside_popup) != "camo" ); ) \
        /* attachment title*/\
        PREPROC_TEXT_DRAW_ALIGNED_EXP( (CHOICE_POPUP_WIDTH+10) 58 256 20 CHOICE_HORIZONTAL_ALIGN CHOICE_VERTICAL_ALIGN, 0 0, "@"+tablelookup("mp/attachmentTable.csv",4,dvarString(ui_attachment_highlighted),3), TEXTSIZE_DEFAULT, 0, 0, ITEM_ALIGN_MIDDLE_LEFT, COLOR_TITLE visible when( dvarString(ui_inside_popup) != "camo" ); ) \
        /* attachment desc unlocked*/\
        PREPROC_TEXT_DRAW_ALIGNED_EXP( (CHOICE_POPUP_WIDTH+10) 80 256 20 CHOICE_HORIZONTAL_ALIGN CHOICE_VERTICAL_ALIGN, 0 0, "@"+tablelookup("mp/attachmentTable.csv",4,dvarString(ui_attachment_highlighted),7), TEXTSIZE_SMALL, 0, 0, ITEM_ALIGN_MIDDLE_LEFT, CHOICE_TEXTCOLOR visible 1 )\

    #define LOCAL_ATTACHMENT_ACTION( attachmentName, groupArg ) \
        setdvar loadout_primary_attachment attachmentName; \
        scriptmenuresponse "loadout_primary_attachment:"groupArg":"attachmentName;\
        close self; \
		scriptMenuResponse "go";
        
    #define LOCAL_ATTACHMENT_ACTION2( attachmentName, groupArg ) \
        setdvar loadout_secondary_attachment attachmentName; \
        scriptmenuresponse "loadout_secondary_attachment:"groupArg":"attachmentName;\
		close self;\
		scriptMenuResponse "go"; \
        PREPROC_ATTACH_CLOSEALL

    #define AI_FOCUS_ACTION( weaponRef ) \
        exec "set ui_attachment_highlighted "weaponRef;

    #define LOCAL_ATTACHMENT_ITEM( itemNum, groupArg, pname, ptype,name)\
        CHOICE_BUTTON_FOCUS_VIS_NOHI( itemNum, "", ;, execnow "set ui_attachment_highlighted "weaponRef;, ;, when(!dvarBool( "attach_allow_"groupArg"_"pname )); ) \
        CHOICE_BUTTON_FOCUS_VIS_NOHI( itemNum, name, LOCAL_ATTACHMENT_ACTION(pname, groupArg ), \
        AI_FOCUS_ACTION(pname), ;, when( ptype == "primary" && dvarBool( "attach_allow_"groupArg"_"pname ) ); ) \
        CHOICE_BUTTON_FOCUS_VIS_NOHI( itemNum, name, LOCAL_ATTACHMENT_ACTION2(pname, groupArg ), \
        AI_FOCUS_ACTION(pname), ;, when( ptype == "secondary" && dvarBool( "attach_allow_"groupArg"_"pname ) ); ) \
        CHOICE_BUTTON_FOCUS_VIS_NOHI( itemNum, "", ;, AI_FOCUS_ACTION(pname), ;, when( !dvarBool( "attach_allow_"groupArg"_"pname ) ); ) \
        CHOICE_DBUTTON_VIS_NOHI( itemNum, name, when( !dvarBool( "attach_allow_"groupArg"_"pname ) ); ) \
        CHOICE_HIGHLIGHT( itemNum, when(dvarBool( "attach_allow_"groupArg"_"pname ) ) ) \
        CHOICE_HIGHLIGHT_CUSTOM( itemNum, HIGHLIGHT_COLOR, COLOR_FOCUSED, when( ( ptype == "primary" && dvarString( loadout_primary_attachment ) == pname ) || ( ptype == "secondary" && dvarString( loadout_secondary_attachment ) == pname ) ) )
		
	
    // hackaround to work for PC's floating mouse unfocusing
    #undef  UI_FOCUSFIRST
    #define UI_FOCUSFIRST "ui_attachment_highlighted"
        
    // primary and second primary attachment items
    //
    // NOTE (ESL-MOD): the ESL ruleset allows FMJ and Extended Mags and no
    // silencer, so the two silencer entries are replaced by those.  The allowed
    // set is still gated per item by the esl_attach_* dvars pushed as
    // attach_allow_<group>_<attachment> (see esl_pushAvailability()).
    // Keep the item numbering and the execKey numbers in step.
    //
    // A sniper popup was added for ESL: the Intervention takes FMJ and Extended
    // Mags.  Do NOT put comments inside this macro - a line that does not end
    // with a backslash terminates it and silently deletes every menuDef in it.
    #define LOCAL_MASTER_ATTACHMENT_GROUP( pos, ptype, y_offset)\
    menuDef { /* assault attachments*/ \
       IMPROVED_POPUP_SETUP_ONOPEN( "ocd_attachment_popup_assault", 7, (CHOICE_X( pos )), (CHOICE_Y( pos )+y_offset), ;, execnow "set "UI_FOCUSFIRST" "REF_ATTACHMENT_NONE"; set ui_inside_popup attachment";, 0 )\
        onClose{execnow "set ui_inside_popup 0";} \
        LOCAL_ATTACHMENT_INFO_WINDOW\
        LOCAL_ATTACHMENT_ITEM( 1,"assault", "none", ptype,"1. None" )\
        LOCAL_ATTACHMENT_ITEM( 2,"assault", "fmj", ptype,"2. FMJ" )\
        LOCAL_ATTACHMENT_ITEM( 3,"assault", "xmags", ptype,"3. Extended Mags" )\
  execKey 1 { LOCAL_ATTACHMENT_ACTION( "none" , "assault" ) }\
  execKey 2 { LOCAL_ATTACHMENT_ACTION( "fmj" , "assault" ) } \
  execKey 3 { LOCAL_ATTACHMENT_ACTION( "xmags" , "assault" ) } \
    }\
    menuDef { /* SMG attachments*/\
       IMPROVED_POPUP_SETUP_ONOPEN( "ocd_attachment_popup_specops", 7, (CHOICE_X( pos )), (CHOICE_Y( pos )+y_offset), ;, execnow "set "UI_FOCUSFIRST" "REF_ATTACHMENT_NONE"; set ui_inside_popup attachment";, 0 )\
        onClose{execnow "set ui_inside_popup 0";} \
        LOCAL_ATTACHMENT_INFO_WINDOW\
        LOCAL_ATTACHMENT_ITEM( 1,"specops", "none", ptype,"1. None" )\
        LOCAL_ATTACHMENT_ITEM( 2,"specops", "fmj", ptype,"2. FMJ" )\
        LOCAL_ATTACHMENT_ITEM( 3,"specops", "xmags", ptype,"3. Extended Mags" )\
  execKey 1 { LOCAL_ATTACHMENT_ACTION( "none" , "specops" ) } \
  execKey 2 { LOCAL_ATTACHMENT_ACTION( "fmj" , "specops" ) } \
  execKey 3 { LOCAL_ATTACHMENT_ACTION( "xmags" , "specops" ) } \
    }\
    menuDef { /* sniper attachments*/ \
       IMPROVED_POPUP_SETUP_ONOPEN( "ocd_attachment_popup_sniper", 7, (CHOICE_X( pos )), (CHOICE_Y( pos )+y_offset), ;, execnow "set "UI_FOCUSFIRST" "REF_ATTACHMENT_NONE"; set ui_inside_popup attachment";, 0 )\
        onClose{execnow "set ui_inside_popup 0";} \
        LOCAL_ATTACHMENT_INFO_WINDOW\
        LOCAL_ATTACHMENT_ITEM( 1,"sniper", "none", ptype,"1. None" )\
        LOCAL_ATTACHMENT_ITEM( 2,"sniper", "fmj", ptype,"2. FMJ" )\
        LOCAL_ATTACHMENT_ITEM( 3,"sniper", "xmags", ptype,"3. Extended Mags" )\
  execKey 1 { LOCAL_ATTACHMENT_ACTION( "none" , "sniper" ) } \
  execKey 2 { LOCAL_ATTACHMENT_ACTION( "fmj" , "sniper" ) } \
  execKey 3 { LOCAL_ATTACHMENT_ACTION( "xmags" , "sniper" ) } \
    }\

    menuDef { /* fake attachment heading for weapons without attachments to be displayed on top of camo popup */
       IMPROVED_POPUP_SETUP_ONOPEN( "ocd_attachment_popup_fake", 6, (CHOICE_X( 1 )), (CHOICE_Y( 1 ) + 44), ;, ;, 0 )
        LOCAL_ATTACHMENT_INFO_WINDOW
        PREPROC_SHADER_DRAW_ALIGNED( 0 -24 (CHOICE_POPUP_WIDTH-4) 22 CHOICE_HORIZONTAL_ALIGN CHOICE_VERTICAL_ALIGN, 0 0, "white", 0.15 0.15 0.17 1, 0, 2, CHOICE_POPUP_BORDER_COLOR )
    }

    // side arm attachment selection ======================================================================
    menuDef { /* pistol attachments*/ /* ESL-MOD: FMJ / Extended Mags, no silencer */
       IMPROVED_POPUP_SETUP_ONOPEN( "ocd_attachment_popup_pistol", 7, (CHOICE_X( 2 )), (CHOICE_Y( 2 )+8-35), ;, execnow "set "UI_FOCUSFIRST" "REF_ATTACHMENT_NONE"; set ui_inside_popup attachment";, 0 )
        onClose{execnow "set ui_inside_popup 0";}
        LOCAL_ATTACHMENT_INFO_WINDOW
        LOCAL_ATTACHMENT_ITEM( 1, "pistol", "none", "secondary","1. None" )
        LOCAL_ATTACHMENT_ITEM( 2, "pistol", "fmj", "secondary","2. FMJ" )
        LOCAL_ATTACHMENT_ITEM( 3, "pistol", "xmags", "secondary","3. Extended Mags" )
  execKey 1 { LOCAL_ATTACHMENT_ACTION2( "none" , "pistol" ) }
  execKey 2 { LOCAL_ATTACHMENT_ACTION2( "fmj" , "pistol" ) }
  execKey 3 { LOCAL_ATTACHMENT_ACTION2( "xmags" , "pistol" ) }
    }
    
    // primary and second primary attachment popup menus
      LOCAL_MASTER_ATTACHMENT_GROUP( 1, "primary", 8-35 )

    // ====================================================================================================
    // side arm selection ===============================================================================
    // ====================================================================================================
    #define LOCAL_SIDEARM_INFO_WINDOW \
        /* sidearm information side frame*/ \
        PREPROC_SHADER_DRAW_ALIGNED( (CHOICE_POPUP_WIDTH-6) -4 280 CHOICE_POPUP_HEIGHT( 6 ) CHOICE_HORIZONTAL_ALIGN CHOICE_VERTICAL_ALIGN, 0 0, "white", CHOICE_POPUP_BORDER_COLOR, 1, 2, CHOICE_POPUP_BORDER_COLOR visible when( dvarString(ui_inside_popup) != "attachment" ); ) \
        LOADOUT_PLATING_RAW( CHOICE_POPUP_WIDTH 8, -4, -2, 280, (CHOICE_POPUP_HEIGHT( 6 )-4), CHOICE_HORIZONTAL_ALIGN CHOICE_VERTICAL_ALIGN visible when( dvarString(ui_inside_popup) != "attachment" );, 0, 0 )\
        /* sidearm image*/ \
        PREPROC_SHADER_DRAW_ALIGNED( (CHOICE_POPUP_WIDTH+6) 30 256 48 CHOICE_HORIZONTAL_ALIGN CHOICE_VERTICAL_ALIGN, 0 0, "gradient_bottom", 1 1 1 0.3, 0, 2, CHOICE_POPUP_BORDER_COLOR visible when( dvarString(ui_inside_popup) != "attachment" ); ) \
        PREPROC_SHADER_DRAW_ALIGNED( (CHOICE_POPUP_WIDTH+72) -6 180 90 CHOICE_HORIZONTAL_ALIGN CHOICE_VERTICAL_ALIGN, 0 0, tablelookup("mp/statsTable.csv",4,dvarString("ui_sidearm_highlighted"),6), 1 1 1 1, 0, 2, CHOICE_POPUP_BORDER_COLOR visible when( dvarString(ui_inside_popup) != "attachment" ); ) \
        /* sidearm title*/\
        PREPROC_TEXT_DRAW_ALIGNED_EXP( (CHOICE_POPUP_WIDTH+10) 58 256 20 CHOICE_HORIZONTAL_ALIGN CHOICE_VERTICAL_ALIGN, 0 0, "@"+tablelookup("mp/statstable.csv",4,dvarString("ui_sidearm_highlighted"),3), TEXTSIZE_DEFAULT, 0, 0, ITEM_ALIGN_MIDDLE_LEFT, COLOR_TITLE visible when( dvarString(ui_inside_popup) != "attachment" ); ) \
        /* sidearm desc unlocked*/\
        PREPROC_TEXT_DRAW_ALIGNED_EXP( (CHOICE_POPUP_WIDTH+10) 80 256 20 CHOICE_HORIZONTAL_ALIGN CHOICE_VERTICAL_ALIGN, 0 0, "@"+tablelookup("mp/statstable.csv",4,dvarString("ui_sidearm_highlighted"),7), TEXTSIZE_SMALL, 0, 0, ITEM_ALIGN_MIDDLE_LEFT, CHOICE_TEXTCOLOR visible 1; )\

    #define LOCAL_SIDEARM_ACTION( weaponRef ) \
            play "mouse_click"; \
            setdvar loadout_secondary weaponRef; \
            setdvar loadout_secondary_attachment none; \
            scriptMenuResponse "loadout_secondary:"weaponRef;\
			scriptMenuResponse "go"; \
            PREPROC_ATTACH_CLOSEALL

    #define LOCAL_SIDEARM_ACTION2( weaponRef ) \
            play "mouse_click"; \
            setdvar loadout_secondary weaponRef; \
            setdvar loadout_secondary_attachment none; \
            scriptMenuResponse "loadout_secondary:"weaponRef;\
			OPENMENUONDVAR(selected_weapon_class,pistol,ocd_attachment_popup_pistol)\
			scriptMenuResponse "go";
    
    #define SI_FOCUS_ACTION( weaponRef ) \
        exec "set ui_sidearm_highlighted "weaponRef;

    // NOTE (ESL-MOD): side arms open the attachment popup, with one exception -
    // the gold Deagle has no attachment in this game at all, so mounting one
    // made the class invalid and the game replaced the pistol with its default
    // one (that is what "gold Deagle + FMJ gives a USP" was).  It goes straight
    // to LOCAL_SIDEARM_ACTION(), which forces the attachment to "none".
    #define LOCAL_SIDEARM_ITEM( itemNum, weaponName, weaponRef )\
        CHOICE_BUTTON_FOCUS_VIS_NOHI( itemNum, "", ;, execnow "set ui_sidearm_highlighted "weaponRef;, ;, when(!dvarBool( "weap_allow_"weaponRef )); ) \
        CHOICE_BUTTON_FOCUS_VIS_NOHI( itemNum, weaponName, LOCAL_SIDEARM_ACTION( weaponRef ), \
        SI_FOCUS_ACTION( weaponRef ), ;, when( dvarBool( "weap_allow_"weaponRef ) && weaponRef == REF_DESERTEAGLEGOLD ); ) \
        CHOICE_BUTTON_FOCUS_VIS_NOHI( itemNum, weaponName, LOCAL_SIDEARM_ACTION2( weaponRef ), \
        SI_FOCUS_ACTION( weaponRef ), ;, when( dvarBool( "weap_allow_"weaponRef ) && weaponRef != REF_DESERTEAGLEGOLD ); ) \
        CHOICE_DBUTTON_VIS_NOHI( itemNum, weaponName, when( !dvarBool( "weap_allow_"weaponRef ) ); ) \
        CHOICE_HIGHLIGHT( itemNum, when(dvarBool( "weap_allow_"weaponRef )) )
    // NOTE (ESL-MOD): no execKey inside this macro on purpose - the hotkeys are
    // declared once at popup level below, so the gold Deagle's "1" can skip the
    // attachment popup (LOCAL_SIDEARM_ACTION) while the other side arms take it
    // (LOCAL_SIDEARM_ACTION2).  Declaring both here and there would leave the
    // parser to decide which wins.
    // side arm selection popup menu

    // hackaround to work for PC's floating mouse unfocusing
    #undef  UI_FOCUSFIRST
    #define UI_FOCUSFIRST "ui_sidearm_highlighted"
    
    menuDef 
    {
       IMPROVED_POPUP_SETUP_ONOPEN( "ocd_popup_cac_secondary", 6, (CHOICE_X( 2 )), (CHOICE_Y( 2 )+8-35), ;, execnow "set "UI_FOCUSFIRST" "REF_DESERTEAGLEGOLD"; set selected_weapon_class pistol; set ui_inside_popup pistol";, 1 )
        onClose{execnow "set ui_inside_popup 0";}
        LOCAL_SIDEARM_INFO_WINDOW
		LOCAL_SIDEARM_ITEM( 1, "1. Gold Desert Eagle", REF_DESERTEAGLEGOLD )
		LOCAL_SIDEARM_ITEM( 2, "2. Desert Eagle", REF_DESERTEAGLE )
		LOCAL_SIDEARM_ITEM( 3, "3. Magnum", REF_COLTANACONDA )
		LOCAL_SIDEARM_ITEM( 4, "4. USP .45", REF_USP )
		LOCAL_SIDEARM_ITEM( 5, "5. M9", REF_M9BERETTA )
		// the hotkeys follow the click actions above: only the gold Deagle skips
		// the attachment step, the Deagle and the Magnum take FMJ
		execKey "1" { LOCAL_SIDEARM_ACTION(REF_DESERTEAGLEGOLD); }
		execKey "2" { LOCAL_SIDEARM_ACTION2(REF_DESERTEAGLE); }
		execKey "3" { LOCAL_SIDEARM_ACTION2(REF_COLTANACONDA); }
		execKey "4" { LOCAL_SIDEARM_ACTION2(REF_USP); }
		execKey "5" { LOCAL_SIDEARM_ACTION2(REF_M9BERETTA); }
    }

    // ====================================================================================================
    // camo skin selection ================================================================================
    // ====================================================================================================
    #define LOCAL_CAMO_INFO_WINDOW \
        /* camo information side frame*/ \
        PREPROC_SHADER_DRAW_ALIGNED( (CHOICE_POPUP_WIDTH-6) -4 280 CHOICE_POPUP_HEIGHT( 9 ) CHOICE_HORIZONTAL_ALIGN CHOICE_VERTICAL_ALIGN, 0 0, "white", CHOICE_POPUP_BORDER_COLOR, 1, 2, CHOICE_POPUP_BORDER_COLOR ) \
        LOADOUT_PLATING_RAW( CHOICE_POPUP_WIDTH 8, -4, -2, 280, (CHOICE_POPUP_HEIGHT( 9 )-4), CHOICE_HORIZONTAL_ALIGN CHOICE_VERTICAL_ALIGN, 0, 0 )\
        /* camo image*/ \
        PREPROC_SHADER_DRAW_ALIGNED( (CHOICE_POPUP_WIDTH+6) 30 256 48 CHOICE_HORIZONTAL_ALIGN CHOICE_VERTICAL_ALIGN, 0 0, "gradient_bottom", 1 1 1 0.3, 0, 2, CHOICE_POPUP_BORDER_COLOR ) \
        PREPROC_SHADER_DRAW_ALIGNED( (CHOICE_POPUP_WIDTH+184) 0 64 64 CHOICE_HORIZONTAL_ALIGN CHOICE_VERTICAL_ALIGN, 0 0, tablelookup("mp/camotable.csv",1,dvarString("ui_camo_highlighted"),4), 1 1 1 0.75, 1, 7, 0.2 0.2 0.225 1 ) \
        /* camo title*/\
        PREPROC_TEXT_DRAW_ALIGNED_EXP( (CHOICE_POPUP_WIDTH+10) 58 256 20 CHOICE_HORIZONTAL_ALIGN CHOICE_VERTICAL_ALIGN, 0 0, "@"+tablelookup("mp/camotable.csv",1,dvarString("ui_camo_highlighted"),2), TEXTSIZE_DEFAULT, 0, 0, ITEM_ALIGN_MIDDLE_LEFT, COLOR_TITLE ) \
        /* camo desc unlocked*/\
        PREPROC_TEXT_DRAW_ALIGNED_EXP( (CHOICE_POPUP_WIDTH+10) 80 256 20 CHOICE_HORIZONTAL_ALIGN CHOICE_VERTICAL_ALIGN, 0 0, "@"+tablelookup("mp/camotable.csv",1,dvarString("ui_camo_highlighted"),3), TEXTSIZE_SMALL, 0, 0, ITEM_ALIGN_MIDDLE_LEFT, CHOICE_TEXTCOLOR visible when( 1 ); )\

    #define LOCAL_CAMO_ACTION( camoRef ) \
            play "mouse_click"; \
            setdvar loadout_camo camoRef;\
            scriptMenuResponse "loadout_camo:"camoRef;\
			scriptMenuResponse "go"; \
            PREPROC_ATTACH_CLOSEALL

    #define LOCAL_CAMO_ITEM( itemNum, camoName, camoRef, visArg )\
        CHOICE_HIGHLIGHT( itemNum, visArg ) \
        CHOICE_BUTTON_FOCUS_VIS_NOHI( itemNum, camoName, LOCAL_CAMO_ACTION( camoRef );, execnow "set ui_camo_highlighted "camoRef;, ;, visArg )  \
        execKey itemNum { LOCAL_CAMO_ACTION( camoRef ) }

    // hackaround to work for PC's floating mouse unfocusing
    #undef  UI_FOCUSFIRST
    #define UI_FOCUSFIRST "ui_camo_highlighted"
    
    // camo skin selection for primary weapon popup menu
    #define LOCAL_CAMO_GROUP( prefix, onLeave )\
    menuDef \
    {\
		IMPROVED_POPUP_SETUP_ONOPEN( "ocd_popup_cac_camo"prefix, 9, (CHOICE_X( 1 )), (CHOICE_Y( 1 )+76-35), ;, execnow "set "UI_FOCUSFIRST" none; set ui_inside_popup camo";, 0 )\
        onClose{onLeave;} \
        LOCAL_CAMO_INFO_WINDOW\
        LOCAL_CAMO_ITEM( 1, "1. None", "none", 1 )\
        LOCAL_CAMO_ITEM( 2, "2. Desert", "desert", 1 )\
        LOCAL_CAMO_ITEM( 3, "3. Arctic", "arctic", 1 )\
        LOCAL_CAMO_ITEM( 4, "4. Woodland", "woodland", 1 )\
        LOCAL_CAMO_ITEM( 5, "5. Digital", "digital", 1 )\
        LOCAL_CAMO_ITEM( 6, "6. Urban", "red_urban", 1 )\
        LOCAL_CAMO_ITEM( 7, "7. Blue Tiger", "blue_tiger", 1 )\
        LOCAL_CAMO_ITEM( 8, "8. Red Tiger", "red_tiger", 1 )\
        LOCAL_CAMO_ITEM( 9, "9. Fall", "orange_fall", 1 )\
    }

    // camo skin selection for primary weapon popup menu
    LOCAL_CAMO_GROUP( "", execnow "set ui_inside_popup attachment" )
    // camo skin selection for primary weapon without attachments
    LOCAL_CAMO_GROUP( "2", execnow "set ui_inside_popup 0"; close "ocd_attachment_popup_fake" )
    
    
    // ====================================================================================================
    // special grenade selection ==========================================================================
    // ====================================================================================================
    #define LOCAL_SGRENADE_INFO_WINDOW \
        /* special grenade information side frame*/ \
        PREPROC_SHADER_DRAW_ALIGNED( (CHOICE_POPUP_WIDTH-6) -4 280 CHOICE_POPUP_HEIGHT(5) CHOICE_HORIZONTAL_ALIGN CHOICE_VERTICAL_ALIGN, 0 0, "white", CHOICE_POPUP_BORDER_COLOR, 1, 2, CHOICE_POPUP_BORDER_COLOR ) \
        LOADOUT_PLATING_RAW( CHOICE_POPUP_WIDTH 8, -4, -2, 280, (CHOICE_POPUP_HEIGHT(5)-4), CHOICE_HORIZONTAL_ALIGN CHOICE_VERTICAL_ALIGN visible when( dvarString(ui_inside_popup) != "attachment" );, 0, 0 )\
        /* special grenade image*/ \
        PREPROC_SHADER_DRAW_ALIGNED( (CHOICE_POPUP_WIDTH+6) 6 256 48 CHOICE_HORIZONTAL_ALIGN CHOICE_VERTICAL_ALIGN, 0 0, "gradient_bottom", 1 1 1 0.3, 0, 2, CHOICE_POPUP_BORDER_COLOR visible when( dvarString(ui_inside_popup) != "attachment" ); ) \
        PREPROC_SHADER_DRAW_ALIGNED( (CHOICE_POPUP_WIDTH+178) -6 64 64 CHOICE_HORIZONTAL_ALIGN CHOICE_VERTICAL_ALIGN, 0 0, tablelookup("mp/statsTable.csv",4,dvarString("ui_sgrenade_highlighted"),6), 1 1 1 1, 0, 2, CHOICE_POPUP_BORDER_COLOR ) \
        /* special grenade title*/\
        PREPROC_TEXT_DRAW_ALIGNED_EXP( (CHOICE_POPUP_WIDTH+10) 34 256 20 CHOICE_HORIZONTAL_ALIGN CHOICE_VERTICAL_ALIGN, 0 0, "@"+tablelookup("mp/statstable.csv",4,dvarString("ui_sgrenade_highlighted"),3), TEXTSIZE_DEFAULT, 0, 0, ITEM_ALIGN_MIDDLE_LEFT, COLOR_TITLE ) \
        /* special grenade desc unlocked*/\
        PREPROC_TEXT_DRAW_ALIGNED_EXP( (CHOICE_POPUP_WIDTH+10) 56 256 20 CHOICE_HORIZONTAL_ALIGN CHOICE_VERTICAL_ALIGN, 0 0, "@"+tablelookup("mp/statstable.csv",4,dvarString("ui_sgrenade_highlighted"),7), TEXTSIZE_SMALL, 0, 0, ITEM_ALIGN_MIDDLE_LEFT, CHOICE_TEXTCOLOR ) \

    #define LOCAL_SGRENADE_ACTION( weaponRef ) \
            play "mouse_click"; \
            setdvar loadout_grenade weaponRef; \
            scriptMenuResponse "loadout_grenade:"weaponRef;\
			scriptMenuResponse "go"; \
            close "ocd_popup_cac_extra"
        
    #define LOCAL_SGRENADE_ITEM( itemNum, weaponName, weaponRef )\
        CHOICE_BUTTON_FOCUS_VIS_NOHI( itemNum, "", ;, execnow "set ui_sgrenade_highlighted "weaponRef;, ;, when(!dvarBool( "weap_allow_"weaponRef )); ) \
        CHOICE_BUTTON_FOCUS_VIS_NOHI( itemNum, weaponName, LOCAL_SGRENADE_ACTION( weaponRef ), \
        execnow "set ui_sgrenade_highlighted "weaponRef, ;, when(dvarBool("weap_allow_"weaponRef))) \
        CHOICE_DBUTTON_VIS_NOHI( itemNum, weaponName, when(!dvarBool("weap_allow_"weaponRef) ); ) \
        CHOICE_HIGHLIGHT( itemNum, when(dvarBool( "weap_allow_"weaponRef )) ) \
        CHOICE_HIGHLIGHT_CUSTOM( itemNum, HIGHLIGHT_COLOR, COLOR_FOCUSED, when( dvarString( loadout_grenade ) == weaponRef ) ) \
        execKey itemNum { LOCAL_SGRENADE_ACTION( weaponRef ) }
		
    // hackaround to work for PC's floating mouse unfocusing
    #undef  UI_FOCUSFIRST
    #define UI_FOCUSFIRST "ui_sgrenade_highlighted"
    
    // ESL-MOD: the lethal slot (equipment) - the frag grenade or the throwing
    // knife.  "lethal_allow_frag" / "lethal_allow_knife" are published by
    // esl_pushAvailability(), and "loadout_lethal" holds the current choice.
    // NOTE (ESL-MOD): the lethal slot lives in its own popup (ocd_popup_cac_lethal),
    // so this must close that one.  It closed ocd_popup_cac_extra - the tactical
    // popup - which left the lethal list open on screen after a pick.
    #define LOCAL_LETHAL_ACTION( equipRef ) \
            play "mouse_click"; \
            setdvar loadout_lethal equipRef; \
            scriptMenuResponse "loadout_lethal:"equipRef;\
   scriptMenuResponse "go"; \
            close "ocd_popup_cac_lethal"

    // statsRef is the mp/statsTable.csv key (no "_mp"), which is what the info
    // window looks up for the icon and the description; equipRef is the value the
    // equipment slot takes, and that one does carry the "_mp" suffix.
    #define LOCAL_LETHAL_ITEM( itemNum, itemName, dvarRef, statsRef, equipRef )\
        CHOICE_BUTTON_FOCUS_VIS_NOHI( itemNum, "", ;, execnow "set ui_sgrenade_highlighted "statsRef;, ;, when(!dvarBool( "lethal_allow_"dvarRef )); ) \
        CHOICE_BUTTON_FOCUS_VIS_NOHI( itemNum, itemName, LOCAL_LETHAL_ACTION( equipRef ), \
        execnow "set ui_sgrenade_highlighted "statsRef, ;, when(dvarBool("lethal_allow_"dvarRef))) \
        CHOICE_DBUTTON_VIS_NOHI( itemNum, itemName, when(!dvarBool("lethal_allow_"dvarRef) ); ) \
        CHOICE_HIGHLIGHT( itemNum, when(dvarBool( "lethal_allow_"dvarRef )) ) \
        CHOICE_HIGHLIGHT_CUSTOM( itemNum, HIGHLIGHT_COLOR, COLOR_FOCUSED, when( dvarString( loadout_lethal ) == equipRef ) ) \
        execKey itemNum { LOCAL_LETHAL_ACTION( equipRef ) }

    // lethal selection popup (its own menu, so the two slots keep their own
    // numbering: 1-2 lethal here, 1-2 tactical in ocd_popup_cac_extra)
    menuDef
    {
       // NOTE: no "set UI_FOCUSFIRST" here on purpose - the mod publishes
       // ui_sgrenade_highlighted as the *current* lethal when the editor opens,
       // so the info window shows what the player is actually carrying instead
       // of always the first entry.
       IMPROVED_POPUP_SETUP_ONOPEN( "ocd_popup_cac_lethal", 6, (CHOICE_X( 3 )), (CHOICE_Y( 3 )+10-35), ;, execnow "set ui_inside_popup sgrenade";, 1 )
        onClose{ execnow "set ui_inside_popup 0"; }
        LOCAL_SGRENADE_INFO_WINDOW
        LOCAL_LETHAL_ITEM( 1, "1. Frag", "frag", "frag_grenade", "frag_grenade_mp" )
        LOCAL_LETHAL_ITEM( 2, "2. Throwing Knife", "knife", "throwingknife", "throwingknife_mp" )
    }

    // tactical (special grenade) selection popup menus
    menuDef 
    {
       IMPROVED_POPUP_SETUP_ONOPEN( "ocd_popup_cac_extra", 6, (CHOICE_X( 3 )), (CHOICE_Y( 3 )+10-35), ;, execnow "set "UI_FOCUSFIRST" "REF_FLASH_X1"; set ui_inside_popup sgrenade";, 1 )
        onClose{ execnow "set ui_inside_popup 0"; }
        LOCAL_SGRENADE_INFO_WINDOW
        LOCAL_SGRENADE_ITEM( 1, "1. Flash", REF_FLASH_X1 )
        LOCAL_SGRENADE_ITEM( 2, "2. Smoke", REF_SMOKE_X1 )
    }
#include "ui/safearea_hd.menu"