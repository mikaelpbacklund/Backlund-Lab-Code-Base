


n = 0;
while n < 10
   n = n+1;
   [~] = storeGlobalData(true);
   iterationTimer = timer('StartDelay', 5, 'TimerFcn', @iterationTimeout);

   tic
   start(iterationTimer)
   continueIterations = input('Continue? 0 or 1\n');
 
    if toc < 5
       [~] = storeGlobalData(false);
    end
    stop(iterationTimer)
    delete(iterationTimer)
    if ~continueIterations
       break
    end
end

function iterationTimeout(HObj,event) %#ok<INUSD>
import java.awt.*;
import java.awt.event.*;
G = storeGlobalData([]);
if G
   rob = Robot;
   rob.keyPress(KeyEvent.VK_1)
   rob.keyRelease(KeyEvent.VK_1)
   rob.keyPress(KeyEvent.VK_ENTER)
   rob.keyRelease(KeyEvent.VK_ENTER)
end
end

function G = storeGlobalData(pressKeys)
persistent geepers
if ~isempty(pressKeys)
   geepers = pressKeys;
end
if isempty(geepers)
   geepers = true;
end
G = geepers;
end