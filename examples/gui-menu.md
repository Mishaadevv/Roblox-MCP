# Example: main menu (GUI)

> You: Make a main menu with Play and Shop buttons.

The agent calls a single tool:

`create_gui`:
```json
{
  "name": "MainMenu",
  "parent": "StarterGui",
  "properties": { "ResetOnSpawn": false, "IgnoreGuiInset": true },
  "children": [
    {
      "className": "Frame",
      "name": "Background",
      "properties": {
        "Size": { "__type": "UDim2", "value": [1, 0, 1, 0] },
        "BackgroundColor3": { "__type": "Color3", "value": [20, 20, 30] }
      },
      "children": [
        {
          "className": "TextLabel",
          "name": "Title",
          "properties": {
            "Text": "MY GAME",
            "Size": { "__type": "UDim2", "value": [0, 400, 0, 80] },
            "Position": { "__type": "UDim2", "value": [0.5, -200, 0.2, 0] },
            "TextScaled": true
          }
        },
        {
          "className": "TextButton",
          "name": "PlayButton",
          "properties": {
            "Text": "PLAY",
            "Size": { "__type": "UDim2", "value": [0, 240, 0, 60] },
            "Position": { "__type": "UDim2", "value": [0.5, -120, 0.45, 0] }
          }
        },
        {
          "className": "TextButton",
          "name": "ShopButton",
          "properties": {
            "Text": "SHOP",
            "Size": { "__type": "UDim2", "value": [0, 240, 0, 60] },
            "Position": { "__type": "UDim2", "value": [0.5, -120, 0.6, 0] }
          }
        }
      ]
    }
  ]
}
```

Then `create_script` (LocalScript inside `MainMenu.Background`) — click handlers:

```lua
local play = script.Parent:WaitForChild("PlayButton")
local shop = script.Parent:WaitForChild("ShopButton")
play.MouseButton1Click:Connect(function()
  script.Parent.Parent.Enabled = false
  print("Play pressed")
end)
shop.MouseButton1Click:Connect(function()
  print("Shop pressed")
end)
```
