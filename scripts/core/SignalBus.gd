extends Node

# UI Navigation (replaces all get_node_or_null path lookups)
signal open_build_menu()
signal open_citizen_panel()
signal open_building_inspector(building: PlacedBuilding)
signal open_town_hall_panel(building: PlacedBuilding)
signal open_market_panel(building: PlacedBuilding)
signal open_magic_tower_panel(building: PlacedBuilding)
signal open_tavern_menu(building: PlacedBuilding)
signal open_quest_panel()
signal open_forage_panel()
signal open_fishing_panel()
signal open_caravan_panel()
signal open_inventory_panel()
signal open_reassign_panel(npc: NPC)
signal open_arrivals_panel()
signal open_revenue_panel()
signal open_trade_port_panel(building: PlacedBuilding)
signal open_guild_hall_panel(building: PlacedBuilding)
signal open_character_profile(npc: NPC)
signal open_festival_panel()
signal open_news_panel()
signal open_kitchen_panel()
signal show_welcome_back(summary: Dictionary)
signal prestige_requested()
signal close_all_panels()
signal build_menu_closed()
signal road_mode_started()
signal road_mode_ended()
signal cancel_road_mode_requested()

# Building interaction
signal building_selected(building: PlacedBuilding)

# Build mode state (so BuildingNodes know not to fire clicks during placement)
var build_mode_active: bool = false

# Notification toast
signal show_notification(message: String)
signal show_notification_timed(message: String, duration: float)
