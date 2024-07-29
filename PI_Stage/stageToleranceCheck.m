function stageToleranceCheck(axisString,targetLocation)
%Checks to see if location is within tolerance range and if not, moves so
%that it is
%targetLocation is the ABSOLUTE position

%Instrument dependencies:
%Coarse XY, coarse Z, and fine XYZ controllers from PI

%Code dependencies:
%InitializationCheck
%stageInitialization

%stageRelativeMove v2.0 4/19/22

global coarseZControl
global coarseXYControl
global fineControl
global master

axlist = master.stage.axes;
truetarg = targetLocation;

if ~isa(truetarg,'double') || ~isscalar(truetarg)
   error("Second input of stageToleranceCheck must be scalar double")
end

switch axisString
   
   %Numerical tag of axis
   case 'x'
      ax = 1;
   case 'y'
      ax = 2;
   case 'z'
      ax = 3;
      
   otherwise
      error("First input of stageToleranceCheck must be 'x', 'y', or 'z'")
end
fax = ax+3;%Fine axis tag

%Check if stage is initialized
InitializationCheck('stage')

%While loop to make sure current position is within specified tolerance
toltries = 0;
tolfails = 0;
while true
    if master.stage.ignoreWait
        break
    end
   
   fineloc = fineControl.qPOS (axlist(fax));
   if ax == 3
      coarseloc = coarseZControl.qPOS (axlist(ax));
      coarseloc = coarseloc * 1000;
   else
      coarseloc = coarseXYControl.qPOS (axlist(ax));
      coarseloc = -coarseloc * 1000;
   end
   
   totalloc = fineloc + coarseloc;
   
   %Sometimes, if both tolerance and pause time are low, the stage gets
   %gets stuck moving back and forth. the pause time will be increased
   %if this happens until the tolerance is reached
   toltries = toltries + 1;
   if toltries > 3
      if master.notifications
         fprintf(['Tolerance not reached after 3 attempts, temporarily adding ' ...
            '.01 seconds to fine pause time and .025 seconds to coarse pause time\n'])
      end
      master.stage.finepause = master.stage.finepause + .01;
      master.stage.coarsepause = master.stage.coarsepause + .025;
      
      %Resets pause expansion counter and adds to failed tolerance
      %counter
      toltries=0;
      tolfails = tolfails+1;
   end
   
   %Finds difference between target and current location and set as new
   %target
   targ = truetarg - totalloc;
   
   if targ > - master.stage.tolerance && targ < master.stage.tolerance
      %Target is within tolerance, movement is finished
      break
      
   elseif (targ + master.stage.loc(fax)) > 200 || targ + master.stage.loc(fax) < 0

       %Target is far out of position so coarse stage will be moved
       stageDirectMove("coarse",axisString,targ)
       pause(master.stage.coarsepause)
      
   else
      %Target is outside of tolerance but not by a large amount,
      %only fine stage is moved
      stageDirectMove("fine",axisString,targ)
      pause(master.stage.finepause)
      
   end
end

%Reverses potential temporary addition to pause time
master.stage.finepause = master.stage.finepause - (tolfails * .01);
master.stage.coarsepause = master.stage.coarsepause - (tolfails * .025);

end

