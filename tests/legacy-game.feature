# Converted from the communitybot legacy tests by kora-qa-panel/scripts/convert-legacy.mjs.
# The """ block under each Scenario is the original test text, verbatim. Review before applying.
Feature: kora_hud — game tests

  @kora_hud @legacy:hud-start @target:1 @needs:admin @manual
  Scenario: Resource starts cleanly
    """
    1. After the server restart (or /server resource kora_hud), watch the server console.
    2. Join and open F8.
    Expect: kora_hud starts with no red errors and no missing dependency (it pulls in kora_theme, kora_fuel and kora_target). The HUD appears once you are spawned in, without a relog.
    """
    When I manually: watch the server console after restarting kora_hud or the server
    Then I confirm: kora_hud starts with no red errors and no missing dependency (kora_theme, kora_fuel, kora_target)
    When I manually: join the server and open F8
    And the F8 console should show no errors
    Then I confirm: the HUD appears once I am spawned in, without a relog

  @kora_hud @legacy:hud-hidden-select @target:2 @checklist @checklist:kora_hud:hidden-at-char-select @cat:character-and-ui
  Scenario: Hidden during loading and character select
    """
    1. Join the server and watch the loading screen, character select, character creation and spawn selection.
    2. Pick a character and spawn.
    Expect: no gauges, money, job pill or vehicle panel show at any point before you are spawned in. The HUD appears as soon as you are in the world.
    Also checklist kora_hud:hidden-at-char-select (HUD hidden during character select): At character selection/spawn cinematic the HUD stays hidden and shows once logged in.
    """
    When I manually: join the server and watch the loading screen, character select, character creation and spawn selection
    Then I confirm: no gauges, money, job pill or vehicle panel show before I am spawned in
    When I manually: pick a character and spawn
    Then the HUD should be visible

  @kora_hud @legacy:hud-logout @target:2
  Scenario: Hides on logout, returns on the next character
    """
    1. While in game, log out or switch character so you are back at character select.
    2. Pick the same or another character.
    Expect: the HUD disappears the moment you leave and stays off on character select. It comes back with the new character's job, money, hunger and thirst, not the old character's.
    """
    When I manually: log out or switch character so I am back at character select
    Then the HUD should be hidden
    When I manually: pick the same or another character
    Then I confirm: the HUD comes back with the new character's job, money, hunger and thirst, not the old character's

  @kora_hud @legacy:hud-health-armour @target:2
  Scenario: Health and armour gauges
    """
    1. Take some damage (fall off something, get hit).
    2. Put on body armour, then take damage again.
    Expect: the health gauge drops and refills smoothly as you heal. The armour gauge fills when you put armour on and drops when it absorbs damage. The game's own health/armour bars under the minimap do not show.
    """
    Given I am at full health
    And my armour is 0
    When I manually: take some damage by falling off something or getting hit
    Then I confirm: the health gauge drops and refills smoothly as I heal
    When I manually: put on body armour
    Then I confirm: the armour gauge fills when I put armour on
    When I manually: take damage again
    Then I confirm: the armour gauge drops when it absorbs damage
    And I confirm: the game's own health and armour bars under the minimap do not show

  @kora_hud @legacy:hud-stamina @target:2 @manual
  Scenario: Stamina gauge
    """
    1. Sprint until you are out of breath, then stand still.
    Expect: the stamina gauge drains while you sprint and refills when you stop, moving smoothly rather than jumping in steps.
    """
    When I manually: sprint until I am out of breath, then stand still
    Then I confirm: the stamina gauge drains while I sprint and refills when I stop
    And I confirm: the stamina gauge moves smoothly rather than jumping in steps

  @kora_hud @legacy:hud-needs @target:2 @checklist @checklist:kora_hud:hunger-thirst @cat:character-and-ui
  Scenario: Hunger and thirst gauges
    """
    1. Note your hunger and thirst gauges.
    2. Eat a food item and drink a drink item.
    3. Play for a while without eating.
    Expect: the gauges go up straight after eating or drinking, without a relog, and slowly go down over time.
    Also checklist kora_hud:hunger-thirst (Hunger and thirst gauges): Eat or drink an item: hunger/thirst gauges change live from the kora_core player data.
    """
    Given I have 1 "burger"
    And I have 1 "water"
    When I manually: note my hunger and thirst gauges
    And I use a "burger"
    And I use a "water"
    Then my metadata "hunger" should have increased
    And my metadata "thirst" should have increased
    And I confirm: the hunger and thirst gauges go up straight after eating or drinking, without a relog
    When I manually: play for a while without eating
    Then I confirm: the hunger and thirst gauges slowly go down over time

  @kora_hud @legacy:hud-death @target:2
  Scenario: HUD after death and respawn
    """
    1. Die (or get downed and give up) and respawn.
    Expect: after respawning the gauges show your new health (full or as set by the respawn). The HUD does not vanish or freeze. The game's own health/armour bars under the minimap stay hidden after the respawn.
    """
    Given I am dead
    When I run the command "/respawn"
    Then I confirm: after respawning the gauges show my new health (full or as set by the respawn)
    And the HUD should be visible
    And I confirm: the HUD does not freeze
    And I confirm: the game's own health and armour bars under the minimap stay hidden after the respawn

  @kora_hud @legacy:hud-job @target:2 @manual
  Scenario: Job and grade pill
    """
    1. Look at the job pill at the bottom right.
    2. Have a Mod change your job or grade, or take a job.
    Expect: it shows your job name and grade (Civilian when unemployed). A change shows within a second, without a relog.
    """
    When I manually: look at the job pill at the bottom right
    Then I confirm: the job pill shows my job name and grade (Civilian when unemployed)
    When I manually: ask a Mod to change my job or grade, or take a job myself
    Then I confirm: the job pill shows the change within a second, without a relog

  @kora_hud @legacy:hud-duty @target:1
  Scenario: On duty / Off duty indicator
    """
    Needs a job with duty (police or EMS). 1. Go on duty and off duty a few times.
    Expect: the job pill shows On duty and Off duty (hover or the icon colour) and switches the moment your duty changes.
    """
    Given my job is "police"
    When I manually: go on duty and off duty a few times
    Then I confirm: the job pill shows On duty and Off duty (hover or icon colour)
    And I confirm: the job pill switches the moment my duty changes

  @kora_hud @legacy:hud-gang @target:1
  Scenario: Gang shown only when in a gang
    """
    1. With no gang, check the bottom right.
    2. Have a Mod put you in a gang, then remove you.
    Expect: no gang pill when you have no gang. In a gang it shows the gang name and rank, and it disappears again when you are removed.
    """
    Given my gang is "none"
    When I manually: check the bottom right of the HUD
    Then I confirm: no gang pill shows when I have no gang
    When I manually: ask a Mod to put me in a gang
    Then I confirm: the gang pill shows the gang name and rank
    When I manually: ask a Mod to remove me from the gang
    Then I confirm: the gang pill disappears

  @kora_hud @legacy:hud-money-scroll @target:2 @manual
  Scenario: Cash and bank take turns
    """
    1. Watch the money row at the bottom right for about 15 seconds.
    Expect: it shows cash, then bank, switching about every 5 seconds with a short fade or slide. Only the money row moves; the job pill and the rest of the HUD stay still.
    """
    When I manually: watch the money row at the bottom right for about 15 seconds
    Then I confirm: the money row shows cash, then bank, switching about every 5 seconds with a short fade or slide
    And I confirm: only the money row moves; the job pill and the rest of the HUD stay still

  @kora_hud @legacy:hud-money-live @target:2
  Scenario: Money updates live
    """
    1. Spend cash in a shop, then receive cash (from a player, a sale or a Mod).
    2. Have bank money change (a transfer, a paycheck or a Mod).
    Expect: the cash and bank amounts change straight away to the right numbers, without a relog. Large amounts are readable and not cut off.
    """
    Given my cash balance is 500
    When I manually: spend cash in a shop
    Then I confirm: the HUD cash amount changes straight away to the right number, without a relog
    When I manually: receive cash from a player, a sale or a Mod
    Then I confirm: the HUD cash amount changes straight away to the right number
    When I manually: change my bank money with a transfer, a paycheck or a Mod
    Then I confirm: the HUD bank amount changes straight away to the right number
    And I confirm: large amounts are readable and not cut off

  @kora_hud @legacy:hud-cash-bank-cmd @target:2 @checklist @checklist:kora_hud:cash-bank-commands @cat:character-and-ui
  Scenario: /cash and /bank
    """
    1. Run /cash, then /bank.
    Expect: each shows a notification (Cash or Bank) with your own current balance, the same as the HUD shows. Nothing else changes and no money is moved.
    Also checklist kora_hud:cash-bank-commands (/cash and /bank): Run /cash and /bank: a notification shows your own balance.
    """
    Given my cash balance is 500
    When I run the command "/cash"
    Then I should see a notification titled "Cash"
    And I confirm: the Cash notification shows my own current balance, the same as the HUD
    When I run the command "/bank"
    Then I should see a notification titled "Bank"
    And I confirm: the Bank notification shows my own current balance, the same as the HUD
    And my cash balance should have changed by 0
    And I confirm: nothing else changes and no money is moved

  @kora_hud @legacy:hud-id @target:2 @checklist @checklist:kora_hud:show-id @cat:character-and-ui
  Scenario: /id shows your server ID
    """
    1. Run /id. Compare the number with what a Mod sees for you (or the player list).
    2. Run /id again.
    3. Run /id once more, then reconnect.
    Expect: the first /id shows your correct server ID on the HUD, the second hides it. After reconnecting it is hidden again until you run /id.
    Also checklist kora_hud:show-id (/id toggles player ID): Run /id: your server ID shows or hides in the player HUD.
    """
    When I run the command "/id"
    Then I confirm: the HUD shows my correct server ID, matching what a Mod or the player list shows
    When I run the command "/id"
    Then I confirm: the server ID is hidden on the HUD
    When I run the command "/id"
    And I manually: reconnect to the server
    Then I confirm: the server ID is hidden on the HUD until I run /id

  @kora_hud @legacy:hud-vehicle-panel @target:2 @checklist @checklist:kora_hud:vehicle-hud @cat:character-and-ui
  Scenario: Vehicle panel in and out of a car
    """
    1. Get into a car as driver, then get out.
    2. Get in as a passenger.
    Expect: the vehicle panel (speed, fuel, engine, headlights, seatbelt) slides in as you get in and slides out as soon as you are out. It also shows as a passenger. Nothing from the vehicle panel stays on screen on foot.
    Also checklist kora_hud:vehicle-hud (Vehicle speed, fuel, engine, lights): Enter a vehicle: speed (km/h or mph), fuel/charge, engine and headlight indicators slide in; they hide on exit.
    """
    Given a "test_car" is spawned in front of me with keys
    When I get in the vehicle
    Then I should be in the driver seat
    And I confirm: the vehicle panel (speed, fuel, engine, headlights, seatbelt) slides in as I get in
    When I get out of the vehicle
    Then I confirm: the vehicle panel slides out as soon as I am out and nothing from it stays on screen on foot
    When I manually: get in the car as a passenger (ask a second player to drive)
    Then I confirm: the vehicle panel also shows as a passenger

  @kora_hud @legacy:hud-speed @target:2
  Scenario: Speedometer
    """
    1. Drive and speed up to about 100, then slow to a stop.
    Expect: the speed shows in km/h with the km/h label, goes up and down smoothly (updates several times a second) and reads 0 when stopped. Say if it feels much higher or lower than the real speed.
    """
    Given I am in the driver seat of a "test_car"
    When I manually: drive and speed up to about 100, then slow to a stop
    Then I confirm: the speed shows in km/h with the km/h label
    And I confirm: the speed goes up and down smoothly, updating several times a second
    And I confirm: the speed reads 0 when stopped
    And I confirm: the speed does not feel much higher or lower than the real speed

  @kora_hud @legacy:hud-fuel @target:2
  Scenario: Fuel gauge
    """
    1. Drive for a while and watch the fuel gauge.
    2. Refuel at a petrol station.
    Expect: the fuel gauge goes down as you drive and fills up while refuelling, matching the fuel kora_fuel shows. A car with a different fuel level shows its own level when you switch cars.
    """
    Given I am in the driver seat of a "test_car"
    When I manually: drive for a while and watch the fuel gauge
    Then I confirm: the fuel gauge goes down as I drive, matching the fuel kora_fuel shows
    When I manually: refuel at a petrol station
    Then I confirm: the fuel gauge fills up while refuelling
    When I manually: switch to a car with a different fuel level
    Then I confirm: the gauge shows that car's own level

  @kora_hud @legacy:hud-ev @target:1 @manual
  Scenario: Electric car shows Charge
    """
    1. Get into an electric car (for example a Voltic, Neon, Raiden, Cyclone or Tezeract).
    2. Then get into a normal petrol car.
    Expect: in the electric car the gauge is labelled Charge instead of Fuel. In the petrol car it says Fuel again.
    """
    When I manually: get into an electric car (Voltic, Neon, Raiden, Cyclone or Tezeract)
    And the HUD should show "Charge"
    And I manually: get into a normal petrol car
    And the HUD should show "Fuel"

  @kora_hud @legacy:hud-engine @target:2
  Scenario: Engine on/off icon
    """
    1. Get into a car with the engine off, start it, then turn it off again (or let it stall).
    Expect: the engine icon shows Engine off and Engine on to match, and changes within a moment of the engine changing.
    """
    Given a "test_car" is spawned in front of me with keys
    And the vehicle engine is off
    When I get in the vehicle
    Then I confirm: the engine icon shows Engine off
    When I turn the engine on
    Then the vehicle engine should be running
    And I confirm: the engine icon shows Engine on within a moment
    When I turn the engine off
    Then the vehicle engine should be off
    And I confirm: the engine icon shows Engine off within a moment

  @kora_hud @legacy:hud-headlights @target:2
  Scenario: Headlights and high beams icon
    """
    1. In a car, press H to cycle the lights: off, on, off. Hold H for high beams.
    Expect: the headlight icon shows Headlights off, Headlights on and High beams on to match what the car's lights are doing.
    """
    Given I am in the driver seat of a "test_car"
    When I manually: press H to cycle the headlights off, on, off
    And I manually: hold H to turn on the high beams
    Then I confirm: my headlight icon shows Headlights off, Headlights on and High beams on to match the car's lights

  @kora_hud @legacy:hud-seatbelt @target:2
  Scenario: Seatbelt icon and sounds
    """
    1. In a car press B (seatbelt) to buckle, then B again to unbuckle.
    2. Get in and out of the car with the belt on and off.
    Expect: the seatbelt icon shows Seatbelt on / Seatbelt off. Buckling plays a click sound and unbuckling a different one. Getting in or out of a car plays no seatbelt sound.
    """
    Given I am in the driver seat of a "test_car"
    When I press the "B" key
    Then the seatbelt indicator should be on
    When I press the "B" key
    Then the seatbelt indicator should be off
    When I get out of the vehicle
    And I get in the vehicle
    And I manually: get in and out of the car once with the belt on and once with the belt off
    Then I confirm: my seatbelt icon shows Seatbelt on and Seatbelt off
    And I confirm: buckling plays a click sound and unbuckling plays a different sound
    And I confirm: getting in or out of the car plays no seatbelt sound

  @kora_hud @legacy:hud-seatbelt-cmd @target:1 @checklist @checklist:kora_hud:seatbelt-toggle @cat:character-and-ui
  Scenario: /hud_toggleseatbelt and rebinding
    """
    1. In a car run /hud_toggleseatbelt twice.
    2. In Settings > Key Bindings > FiveM rebind "Toggle Seatbelt" to another key and use it.
    Expect: the command buckles and unbuckles the same as B, with the icon and sound. The new key works and B no longer does.
    Also checklist kora_hud:seatbelt-toggle (Seatbelt toggle (B / /hud_toggleseatbelt)): In a vehicle press B or run /hud_toggleseatbelt: seatbelt icon toggles and a buckle/unbuckle sound plays.
    """
    Given I am in the driver seat of a "test_car"
    When I run the command "/hud_toggleseatbelt"
    Then the seatbelt indicator should be on
    When I run the command "/hud_toggleseatbelt"
    Then the seatbelt indicator should be off
    And I confirm: the command buckles and unbuckles with the same icon and sound as B
    When I manually: in Settings > Key Bindings > FiveM rebind "Toggle Seatbelt" to another key and press it
    Then I confirm: the new key toggles the seatbelt and B no longer does

  @kora_hud @legacy:hud-harness @target:1
  Scenario: Race harness icon
    """
    Needs a race harness. 1. In a car attach a race harness (/raceharness or the item), then remove it.
    Expect: a race harness icon shows next to the seatbelt only while the harness is attached and goes away when it is removed. The gauges do not jump up while the harness bar is shown.
    """
    Given I am in the driver seat of a "test_car"
    When I manually: attach a race harness (/raceharness or the item), then remove it
    Then I confirm: a race harness icon shows next to the seatbelt only while the harness is attached and goes away when removed
    And I confirm: the gauges do not jump up while the harness bar is shown

  @kora_hud @legacy:hud-stress-speed @target:2
  Scenario: Stress from fast driving
    """
    1. As the driver, drive at 180 km/h or more for at least 30 seconds.
    2. Repeat as a passenger.
    Expect: the stress gauge goes up a little roughly every 10 seconds while you drive that fast, and not below 180. Passengers gain nothing from speed.
    """
    Given I am in the driver seat of a "test_car"
    When I manually: drive at 180 km/h or more for at least 30 seconds
    Then I confirm: my stress gauge goes up a little roughly every 10 seconds, and not below 180 km/h
    When I manually: repeat as a passenger (ask a second player to drive at 180 km/h or more)
    Then I confirm: my stress gauge does not go up as a passenger

  @kora_hud @legacy:hud-stress-shoot @target:2
  Scenario: Stress from shooting
    """
    1. Fire a pistol or rifle a number of times (at a range, or with a Mod around).
    2. Then punch or use a melee weapon.
    Expect: about half of the shots a few seconds apart raise stress by a little. Melee and fists never raise it. Rapid fire does not raise it on every bullet.
    """
    Given I have a "weapon_pistol" equipped with 30 ammo
    When I manually: fire the pistol a number of times
    Then I confirm: about half of the shots a few seconds apart raise my stress by a little
    And I confirm: rapid fire does not raise stress on every bullet
    When I manually: punch with fists or use a melee weapon
    Then I confirm: melee and fists do not raise my stress

  @kora_hud @legacy:hud-stress-police @target:1
  Scenario: Police gain no stress
    """
    Needs a police tester. 1. As police, drive over 180 km/h for 30 seconds and fire your weapon several times.
    Expect: your stress gauge does not go up at all.
    """
    Given my job is "police"
    And I am on duty
    And I am in the driver seat of a "test_car"
    And I have a "weapon_pistol" equipped with 30 ammo
    When I manually: drive over 180 km/h for 30 seconds
    And I manually: fire my weapon several times
    Then I confirm: my stress gauge does not go up at all

  @kora_hud @legacy:hud-stress-save @target:2
  Scenario: Stress is kept after relog
    """
    1. Gain some stress (fast driving or shooting) and note the gauge.
    2. Log out to character select and back in, or reconnect.
    Expect: the stress gauge shows the same amount as before, not 0.
    """
    When I run the command "/hudtest_stress"
    And I manually: note the stress gauge
    And I manually: log out to character select and back in, or reconnect
    Then I confirm: my stress gauge shows the same amount as before, not 0

  @kora_hud @legacy:hud-status @target:2 @checklist @checklist:kora_hud:status-effects @cat:character-and-ui @manual
  Scenario: Status effects at the top right
    """
    1. Get an effect such as Bleeding or Limping (take a bad hit or a fall).
    2. Get it treated or wait for it to clear.
    Expect: the effect shows at the top right while it is active and goes away as soon as it clears.
    Also checklist kora_hud:status-effects (Status effects panel): Get an effect such as Bleeding or Limping: it appears top-right with its severity and clears when healed.
    """
    When I manually: get a status effect such as Bleeding or Limping (take a bad hit or a fall)
    Then I confirm: the effect shows at the top right while active
    When I manually: get it treated or wait for it to clear
    Then I confirm: the effect goes away as soon as it clears

  @kora_hud @legacy:hud-minimap-vehicle @target:2 @checklist @checklist:kora_hud:minimap-vehicle-only @cat:character-and-ui
  Scenario: Minimap only shows in a vehicle
    """
    1. Walk around on foot, then get into a car (driver and passenger), then get out.
    Expect: by default the minimap is hidden on foot and shows the moment you are in any seat of a vehicle, then hides again when you get out.
    Also checklist kora_hud:minimap-vehicle-only (Minimap shown in vehicle only): With default config the radar appears in any seat of a vehicle and is hidden on foot.
    """
    Given a "test_car" is spawned in front of me
    When I manually: walk around on foot
    Then the minimap should be hidden
    When I get in the vehicle
    Then the minimap should be visible
    And I confirm: the minimap also shows when I sit in a passenger seat of a vehicle
    When I get out of the vehicle
    Then the minimap should be hidden

  @kora_hud @legacy:hud-minimap-square @target:2
  Scenario: Square minimap looks right
    """
    1. In a car, look at the minimap while driving and turning.
    2. If you can, also check at a different resolution or an ultrawide screen.
    Expect: the minimap is square and the map stays inside its border while it rotates (nothing spills out of the corners). Say your resolution if it looks off.
    """
    Given I am in the driver seat of a "test_car"
    When I manually: look at the minimap while driving and turning
    Then I confirm: the minimap is square
    And I confirm: the map stays inside its border while rotating with nothing spilling out of the corners
    When I manually: if possible, check at a different resolution or an ultrawide screen
    Then I confirm: the minimap still looks right at that resolution

  @kora_hud @legacy:hud-bigmap @target:2
  Scenario: No stuck oversized minimap
    """
    1. Press Z (or hold your expand-map key) to expand the minimap, then let go.
    2. Die and respawn, and open and close the pause menu.
    Expect: the minimap returns to its normal square size each time and never stays stuck large.
    """
    When I press the "Z" key
    And I manually: let go of the expand-map key
    Then I confirm: the minimap returns to its normal square size
    When I manually: die and respawn
    Then I confirm: the minimap is its normal square size and not stuck large
    When I press the "ESCAPE" key
    And I press the "ESCAPE" key
    Then I confirm: the minimap is its normal square size and not stuck large

  @kora_hud @legacy:hud-minimap-toggle @target:2 @checklist @checklist:kora_hud:minimap-toggle @cat:character-and-ui
  Scenario: /minimap toggle, saved
    """
    1. On foot run /minimap: you get "Minimap shown." and it shows on foot.
    2. Run /minimap again: "Minimap hidden." and it stays hidden even in a car.
    3. Reconnect.
    Expect: each run flips it with the matching notification, and your last choice is still in effect after reconnecting.
    Also checklist kora_hud:minimap-toggle (/minimap toggle): Run /minimap or the Toggle minimap keybind: radar hides/shows with a Minimap notification; choice is remembered after relog.
    """
    When I run the command "/minimap"
    Then I should see a notification containing "Minimap shown."
    And the minimap should be visible
    When I run the command "/minimap"
    Then I should see a notification containing "Minimap hidden."
    When I manually: get into a car
    Then the minimap should be hidden
    When I manually: reconnect
    Then I confirm: my last minimap choice is still in effect after reconnecting

  @kora_hud @legacy:hud-minimap-key @target:1 @manual
  Scenario: Minimap toggle key binding
    """
    1. In Settings > Key Bindings > FiveM find "Toggle minimap" (unbound by default) and bind a key.
    2. Press it a few times on foot and in a car.
    Expect: the key does the same as /minimap, with the same notifications.
    """
    When I manually: in Settings > Key Bindings > FiveM find "Toggle minimap" and bind a key
    And I manually: press the key a few times on foot and in a car
    Then I confirm: the key toggles the minimap the same as /minimap
    And I confirm: it shows the notifications "Minimap shown." and "Minimap hidden."

  @kora_hud @legacy:hud-pause @target:2 @checklist @checklist:kora_hud:hide-on-pause @cat:character-and-ui
  Scenario: HUD hides on the pause menu and map
    """
    1. Press Escape to open the pause menu, then close it.
    2. Press P to open the full map, then close it.
    Expect: all of the HUD (gauges, money, job, status effects, vehicle panel) hides while the menu or map is open, so nothing covers the map legend, and comes back exactly as before when it closes.
    Also checklist kora_hud:hide-on-pause (HUD hides in pause menu/map): Open the pause menu or full map: HUD disappears and returns when closed.
    """
    When I press the "ESCAPE" key
    Then the HUD should be hidden
    And I confirm: all of the HUD (gauges, money, job, status effects, vehicle panel) hides while the menu is open
    When I press the "ESCAPE" key
    Then the HUD should be visible
    And I confirm: the HUD comes back exactly as before when it closes
    When I press the "P" key
    Then the HUD should be hidden
    And I confirm: all of the HUD hides while the map is open so nothing covers the map legend
    When I press the "P" key
    Then the HUD should be visible
    And I confirm: the HUD comes back exactly as before when the map closes

  @kora_hud @legacy:hud-clothing-hide @target:2
  Scenario: Hidden in the clothing menu
    """
    1. Open a clothing shop, barber or tattoo menu, then close it.
    Expect: the HUD and the minimap hide while the menu is open and come back when you close it. On foot the minimap does not come back by mistake (it should follow the vehicle-only rule).
    """
    When I manually: open a clothing shop, barber or tattoo menu
    Then the HUD should be hidden
    And the minimap should be hidden
    When I manually: close the menu
    Then the HUD should be visible
    And the minimap should be hidden
    And I confirm: on foot the minimap does not come back (it follows the vehicle-only rule)

  @kora_hud @legacy:hud-ui-open @target:2
  Scenario: /ui opens the layout editor
    """
    1. Run /ui. Press Escape. Then try /hudsettings and /hudlayout.
    Expect: each opens the same editor: the screen dims, a UI layout panel shows at the top with an element dropdown, and the mouse works. Escape closes it without saving and hands control back to the game.
    """
    When I run the command "/ui"
    Then I confirm: the editor opens, the screen dims, a UI layout panel with an element dropdown shows at the top and the mouse works
    When I press the "ESCAPE" key
    Then I confirm: the editor closes without saving and control returns to the game
    When I run the command "/hudsettings"
    Then I confirm: the same editor opens
    When I press the "ESCAPE" key
    And I run the command "/hudlayout"
    Then I confirm: the same editor opens

  @kora_hud @legacy:hud-ui-move @target:2
  Scenario: Move HUD sections and save
    """
    1. In /ui drag the Move handle of the gauges, the player info and money, and the status effects to new places. Try holding Ctrl (grid) and Shift (45 degrees) while dragging.
    2. Press Confirm, then reconnect.
    Expect: sections follow the mouse, snap with Ctrl and Shift, cannot be pushed off screen, and stay where you put them after reconnecting.
    """
    When I run the command "/ui"
    And I manually: drag the Move handle of the gauges, the player info and money, and the status effects to new places
    And I manually: hold Ctrl (grid) and Shift (45 degrees) while dragging
    Then I confirm: sections follow the mouse and snap with Ctrl and Shift
    And I confirm: sections cannot be pushed off screen
    When I manually: press Confirm, then reconnect
    Then I confirm: the sections stay where I put them after reconnecting

  @kora_hud @legacy:hud-ui-cancel @target:2
  Scenario: Cancel throws changes away
    """
    1. In /ui move and resize a few sections.
    2. Press Close without saving (or Escape).
    Expect: every section jumps back to where it was when you opened the editor and nothing was saved. Opening /ui again shows the old positions.
    """
    When I run the command "/ui"
    And I manually: move and resize a few sections
    And I manually: press Close without saving (or Escape)
    Then I confirm: every section jumps back to where it was when I opened the editor
    When I run the command "/ui"
    Then I confirm: the editor shows the old positions and nothing was saved

  @kora_hud @legacy:hud-ui-resize @target:2
  Scenario: Resize HUD sections
    """
    1. In /ui drag the Resize grip of a section left and right as far as it goes.
    2. Confirm.
    Expect: the section grows and shrinks smoothly between about 75% and 150% and stops at those limits. The new size is kept after Confirm and after reconnecting.
    """
    When I run the command "/ui"
    And I manually: drag the Resize grip of a section left and right as far as it goes
    Then I confirm: the section grows and shrinks smoothly between about 75% and 150% and stops at those limits
    When I manually: click Confirm in the editor
    Then I confirm: the new size is kept after Confirm
    When I manually: reconnect to the server
    Then I confirm: the new size is kept after reconnecting

  @kora_hud @legacy:hud-ui-align @target:1
  Scenario: Align button
    """
    1. In /ui click the Align icon of the player info and money section several times.
    Expect: the content inside the section cycles Left, Centre, Right while the section itself stays where it is. Confirm keeps the choice.
    """
    When I run the command "/ui"
    And I manually: click the Align icon of the player info and money section several times
    Then I confirm: the content inside the section cycles Left, Centre, Right while the section stays where it is
    When I manually: click Confirm in the editor
    Then I confirm: the chosen alignment is kept after Confirm

  @kora_hud @legacy:hud-ui-hide @target:2
  Scenario: Hide an element with Visible
    """
    1. In /ui pick an element from the dropdown (or click it on screen) and switch Visible off. Confirm.
    2. Reconnect, then open /ui and switch it back on.
    Expect: the element disappears from the HUD after Confirm and stays hidden after reconnecting. Turning Visible on brings it back.
    """
    When I run the command "/ui"
    And I manually: pick an element from the dropdown, or click it on screen, and switch Visible off
    And I manually: click Confirm in the editor
    Then I confirm: the element disappears from the HUD
    When I manually: reconnect to the server
    Then I confirm: the element is still hidden after reconnecting
    When I run the command "/ui"
    And I manually: switch Visible back on for that element
    Then I confirm: the element comes back on the HUD

  @kora_hud @legacy:hud-ui-chat @target:2
  Scenario: Chat in the /ui editor
    """
    1. In /ui select Chat. Move and resize it, and change Fade messages after, Background opacity and Show new messages while chat is closed. Confirm.
    2. Open chat with T and send a message.
    Expect: the chat box sits where you put it, at the new size, and the settings take effect. Chat was closed while the editor was open.
    """
    When I run the command "/ui"
    And I manually: select Chat in the editor
    And I manually: move and resize the chat, and change Fade messages after, Background opacity and Show new messages while chat is closed
    And I manually: click Confirm in the editor
    And I press the "T" key
    And I manually: type a message and send it
    Then I confirm: the chat box sits where I put it, at the new size
    And I confirm: the changed chat settings take effect
    And I confirm: chat was closed while the editor was open

  @kora_hud @legacy:hud-ui-inventory @target:2
  Scenario: Inventory in the /ui editor
    """
    1. In /ui select Inventory. Move it and change Personal inventory side and Use my position for stashes and trunks. Confirm.
    2. Open your inventory, then a stash or trunk.
    Expect: the inventory opens where you placed it, and with a stash or trunk your side and position follow the settings you chose.
    """
    When I run the command "/ui"
    And I manually: select Inventory in the editor
    And I manually: move the inventory and change Personal inventory side and Use my position for stashes and trunks
    And I manually: click Confirm in the editor
    And I open my inventory
    Then I confirm: the inventory opens where I placed it
    When I manually: open a stash or a vehicle trunk
    Then I confirm: my side and position follow the settings I chose

  @kora_hud @legacy:hud-ui-minimap @target:2
  Scenario: Move and resize the minimap
    """
    1. Get in a car. In /ui select Minimap, drag its box and resize it. Confirm.
    2. Drive around, then reconnect.
    Expect: the minimap moves and resizes when you drop the box, the map stays inside its square border, and the new spot is kept after reconnecting.
    """
    Given I am in the driver seat of a "test_car"
    When I run the command "/ui"
    And I manually: select Minimap, drag its box and resize it
    And I manually: click Confirm in the editor
    Then I confirm: the minimap moves and resizes when I drop the box
    When I manually: drive around
    Then I confirm: the map stays inside its square border
    When I manually: reconnect to the server
    Then I confirm: the new minimap spot is kept after reconnecting

  @kora_hud @legacy:hud-ui-vehicle-only @target:2
  Scenario: Minimap only in vehicle switch
    """
    1. On foot open /ui and find Minimap only in vehicle. Switch it off and Confirm.
    2. Switch it back on and Confirm.
    Expect: with it off the minimap shows on foot too. With it on the minimap is hidden on foot and shows in a vehicle. The choice is kept after reconnecting.
    """
    Given a "test_car" is spawned in front of me with keys
    When I run the command "/ui"
    And I manually: find Minimap only in vehicle, switch it off and click Confirm
    Then the minimap should be visible
    When I run the command "/ui"
    And I manually: switch Minimap only in vehicle back on and click Confirm
    Then the minimap should be hidden
    When I get in the vehicle
    Then the minimap should be visible
    When I manually: reconnect to the server
    Then I confirm: the choice is kept after reconnecting

  @kora_hud @legacy:hud-ui-anchor @target:1
  Scenario: Gauges anchor toggle
    """
    1. With the gauge Anchor on (default), get in and out of a car.
    2. In /ui turn the gauges Anchor off, Confirm, and get in and out of a car again.
    Expect: anchored, the gauges sit near the bottom on foot and move up above the vehicle panel in a car. With Anchor off they stay at their fixed spot.
    """
    Given a "test_car" is spawned in front of me with keys
    When I get in the vehicle
    Then I confirm: with Anchor on the gauges move up above the vehicle panel in the car
    When I get out of the vehicle
    Then I confirm: the gauges sit near the bottom on foot
    When I run the command "/ui"
    And I manually: turn the gauges Anchor off and click Confirm
    And I get in the vehicle
    And I get out of the vehicle
    Then I confirm: with Anchor off the gauges stay at their fixed spot

  @kora_hud @legacy:hud-ui-dock @target:1
  Scenario: Editor panel top or bottom
    """
    1. In /ui press the arrow on the editor panel to move it to the bottom, then back to the top.
    Expect: the panel moves to the bottom of the screen and back, and still works in both places (dropdown, Visible, Size, Reset).
    """
    When I run the command "/ui"
    And I manually: press the arrow on the editor panel to move it to the bottom
    Then I confirm: the panel moves to the bottom of the screen and the dropdown, Visible, Size and Reset still work
    When I manually: press the arrow again to move the panel back to the top
    Then I confirm: the panel is back at the top and the dropdown, Visible, Size and Reset still work

  @kora_hud @legacy:hud-ui-reset @target:2
  Scenario: Reset an element and Reset all
    """
    1. In /ui move several elements, select one and press its Reset button.
    2. Press Reset all once, then again when asked (Confirm reset).
    Expect: the single reset only moves that element back. Reset all needs the second press, then everything goes back to the default layout.
    """
    When I run the command "/ui"
    And I manually: move several elements
    And I manually: select one element and press its Reset button
    Then I confirm: only that element moved back to its default
    When I manually: press Reset all once
    Then I confirm: Reset all asks for a second press (Confirm reset)
    When I manually: press Confirm reset
    Then I confirm: everything goes back to the default layout

  @kora_hud @legacy:hud-uireset @target:2
  Scenario: /uireset and /hudlayoutreset
    """
    1. Move and hide some elements in /ui and Confirm.
    2. Run /uireset. Make some changes again, then run /hudlayoutreset.
    Expect: each command, without opening anything, puts every element back to its default position, size and visibility, and shows "HUD layout reset to defaults."
    """
    When I run the command "/ui"
    And I manually: move and hide some elements and click Confirm
    And I run the command "/uireset"
    Then I confirm: every element is back at its default position, size and visibility without opening anything
    And I should see a notification containing "HUD layout reset to defaults."
    When I run the command "/ui"
    And I manually: make some changes and click Confirm
    And I run the command "/hudlayoutreset"
    Then I confirm: every element is back at its default position, size and visibility without opening anything
    And I should see a notification containing "HUD layout reset to defaults."

  @kora_hud @legacy:hud-progress-lift @target:1
  Scenario: Gauges lift above a progress bar in a car
    """
    1. Sitting in a car, start something with a progress bar (eat or drink in the car, or use an item).
    Expect: while the bar is shown the gauge row moves up so it does not cover the progress bar, then drops back when the bar ends.
    """
    Given I am in the driver seat of a "test_car"
    And I have 1 "water"
    When I use a "water"
    Then a progress bar should run
    And I confirm: while the progress bar is shown the gauge row moves up and does not cover it
    And I confirm: the gauge row drops back when the bar ends

  @kora_hud @legacy:hud-restart @target:1 @needs:admin
  Scenario: HUD survives a kora_hud restart
    """
    Needs a Mod. 1. While players are in a car, run /server resource kora_hud.
    Expect: the HUD disappears briefly and comes back with the right values, without a relog. The minimap is not left hidden, stuck large or with the wrong shape, and saved layouts are kept.
    """
    Given I am in the driver seat of a "test_car"
    When I manually: ask a Mod to run /server resource kora_hud while I am in the car
    Then I confirm: the HUD disappears briefly and comes back with the right values without a relog
    And the minimap should be visible
    And I confirm: the minimap is not stuck large or with the wrong shape
    And I confirm: my saved layout is kept

  @kora_hud @legacy:hud-performance @target:1 @manual
  Scenario: Low resource use
    """
    1. Open F8 and run resmon 1.
    2. Find kora_hud standing still, sprinting, and driving.
    Expect: kora_hud uses very little (close to 0.00 ms standing still and only a little more while driving). Say the numbers you see and whether you notice any FPS drop with the HUD on.
    """
    When I manually: open F8 and run resmon 1
    And I manually: find kora_hud in the list while standing still, sprinting and driving
    Then I confirm: kora_hud uses close to 0.00 ms standing still and only a little more while driving
    And I confirm: I notice no FPS drop with the HUD on (note the numbers I saw)

  @kora_hud @legacy:hud-mic @target:2 @checklist @checklist:kora_hud:mic-indicator @cat:character-and-ui @manual
  Scenario: Mic indicator lights up when talking
    """
    1. Make sure Voice Chat is on in Settings > Voice Chat.
    2. Talk normally for a few seconds, then stop.
    Expect: the round mic icon at the bottom right glows green and pulses while you talk and goes back to grey within a moment of stopping. It does not stay lit when you are silent.
    Also checklist kora_hud:mic-indicator (Voice mic indicator): Talk in voice chat: mic pill lights up and shows talking mode/range when the voice resource exposes it.
    """
    When I manually: make sure Voice Chat is on in Settings > Voice Chat
    And I manually: talk normally for a few seconds, then stop
    Then I confirm: the round mic icon at the bottom right glows green and pulses while I talk
    And I confirm: the mic icon goes back to grey within a moment of stopping and does not stay lit when I am silent

  @kora_hud @legacy:hud-mic-range @target:2 @manual
  Scenario: Mic icon shows your voice range
    """
    1. Press the ` key (left of 1) to step through Whisper, Normal, Shout.
    2. Hover or look at the mic icon after each press.
    Expect: the icon changes with the range (fewer sound waves for Whisper, more for Shout) and the tooltip says Voice range: Whisper / Normal talk / Shout to match the notification.
    """
    When I manually: press the ` key to step through Whisper, Normal, Shout
    And I manually: hover or look at the mic icon after each press
    Then I confirm: the icon changes with the range, fewer sound waves for Whisper and more for Shout
    And I confirm: the tooltip says Voice range: Whisper / Normal talk / Shout to match the notification
