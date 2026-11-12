# Converted from the communitybot legacy tests by kora-qa-panel/scripts/convert-legacy.mjs.
# The """ block under each Scenario is the original test text, verbatim. Review before applying.
Feature: kora_hud — Character & UI

  @kora_hud @checklist @checklist:kora_hud:hud-gauges @cat:character-and-ui @manual
  Scenario: Health, armour, stamina gauges
    """
    Checklist test: Take damage, wear armour and sprint: HUD gauges update; with dynamic mode on, gauges hide at their neutral value.
    """
    When I manually: take some damage and wear armour
    And I manually: sprint for a few seconds
    Then I confirm: the health, armour and stamina gauges update
    And I confirm: with Config.hud.dynamic enabled, gauges hide at their neutral value (otherwise mark Pass if they stay visible)

  @kora_hud @checklist @checklist:kora_hud:stress-gauge @cat:character-and-ui @manual
  Scenario: Stress gauge
    """
    Checklist test: Gain stress (e.g. shooting, speeding if enabled): stress gauge appears and falls back; off if elements.stress is false.
    """
    When I manually: gain stress, for example by shooting or speeding (if enabled)
    Then I confirm: the stress gauge appears
    And I confirm: the stress gauge falls back over time
    And I confirm: no stress gauge shows when Config.hud.elements.stress is false (only applies then; otherwise mark Pass)

  @kora_hud @checklist @checklist:kora_hud:money-display @cat:character-and-ui
  Scenario: Cash and bank display
    """
    Checklist test: Earn or spend money: cash and bank pills update; with scrollAccounts they alternate every 5s.
    """
    Given my cash balance is 500
    When I run the command "/hudtest_cash"
    And I run the command "/hudtest_bank"
    Then I confirm: my cash and bank pills update to show the new amounts
    And I confirm: with Config.hud.money.scrollAccounts enabled the cash and bank pills alternate every 5 seconds (otherwise mark Pass if both show side by side)

  @kora_hud @checklist @checklist:kora_hud:job-gang-pill @cat:character-and-ui @manual
  Scenario: Job and gang display
    """
    Checklist test: Change job/grade/duty or gang via admin: job and gang pills update with label and grade.
    """
    When I manually: ask an admin to change my job, grade, duty status or gang
    Then I confirm: my job pill updates with the new job label and grade
    And I confirm: my gang pill updates with the new gang label and grade

  @kora_hud @checklist @checklist:kora_hud:hud-layout-editor @cat:character-and-ui @manual
  Scenario: /hudlayout editor
    """
    Checklist test: Run /hudlayout: move, resize (75-150%) and align sections, use Control/Shift snapping, then Confirm to save or Cancel/Esc to revert.
    """
    When I manually: run /hudlayout
    Then I confirm: the layout editor opens (only applies when moving is enabled; otherwise "Moving HUD sections is disabled on this server." shows)
    When I manually: move a section, resize it between 75% and 150% and use the align button
    And I manually: hold Control or Shift while moving to use snapping
    Then I confirm: sections move, resize, align and snap as expected
    When I manually: click Confirm to save
    Then I confirm: the layout is saved
    When I manually: change a section and then click Cancel or press Esc
    Then I confirm: the changes revert

  @kora_hud @checklist @checklist:kora_hud:hud-layout-reset @cat:character-and-ui
  Scenario: /hudlayoutreset and layout persistence
    """
    Checklist test: Save a layout and relog to confirm it persists; /hudlayoutreset restores the default positions.
    """
    When I manually: run /hudlayout, move a section and save
    And I manually: relog
    Then I confirm: my saved layout persists
    When I run the command "/hudlayoutreset"
    Then I should see a notification containing "HUD layout reset to defaults."
    And I confirm: the HUD sections are back in their default positions

  @kora_hud @checklist @checklist:kora_hud:hud-exports @cat:character-and-ui @needs:admin
  Scenario: hide/show/isVisible exports
    """
    Checklist test: Call exports.kora_hud:hide(), show() and isVisible() from a client script and see the HUD respond.
    """
    When I manually: run exports.kora_hud:hide() from the F8 console or a client script
    Then the HUD should be hidden
    When I manually: run print(exports.kora_hud:isVisible()) from the F8 console
    And the F8 console should show "false"
    And I manually: run exports.kora_hud:show() from the F8 console or a client script
    Then the HUD should be visible
    When I manually: run print(exports.kora_hud:isVisible()) from the F8 console
    And the F8 console should show "true"

  @kora_hud @checklist @checklist:kora_hud:qb-hud-events @cat:character-and-ui @needs:admin @manual
  Scenario: qb-hud compat events
    """
    Checklist test: Trigger hud:client:UpdateNeeds / UpdateStress events from another resource: gauges overlay the value on display only.
    """
    When I manually: run TriggerEvent('hud:client:UpdateNeeds') and TriggerEvent('hud:client:UpdateStress') with test values from the F8 console or a client script
    Then I confirm: the hunger, thirst and stress gauges show the overlaid values on display only
    And I confirm: my actual needs and stress values are unchanged
