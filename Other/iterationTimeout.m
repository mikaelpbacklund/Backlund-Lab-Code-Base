function iterationTimeout(HObj,event) %#ok<INUSD>
%Designed to be used as a timer function
%Imports and creates a basic "robot" from java that can press keys

   import java.awt.*;
  import java.awt.event.*;
  rob = Robot;
  globalData = pseudoGlobalData([]); %Check if robot should press keys
  if ~isfield(globalData,'robotPressKeys') || globalData.robotPressKeys
     rob.keyPress(KeyEvent.VK_1)
     rob.keyRelease(KeyEvent.VK_1)
     rob.keyPress(KeyEvent.VK_ENTER)
     rob.keyRelease(KeyEvent.VK_ENTER)
  end
end