function stageFineReset(axisString,minMaxCenter)
%Resets fine axis to specified spot while keeping overall location
%constant

%Instrument dependencies:
%Coarse XY, coarse Z, and fine XYZ controllers from PI

%Code dependencies:
%InitializationCheck
%stageInitialization
%stageDirectMove
%stageToleranceCheck

%stageFineReset v2.0 4/19/22

global master
global fineControl
global coarseXYControl
global coarseZControl

switch axisString
   
   %Numerical tag of axis
   case 'x'
      ax = 1;
   case 'y'
      ax = 2;
   case 'z'
      ax = 3;
      
   otherwise
      error("First input of stageFineReset must be 'x', 'y', or 'z'")
end
fax = ax+3;%Fine axis tag
axlist = master.stage.axes;

mintrue = false;
maxtrue = false;
centertrue = false;
switch minMaxCenter
   
   case 'min'
      mintrue = true;
      if master.notifications
      fprintf('Performing min fine axis reset\n')
      end
   case 'max'
      maxtrue = true;
      if master.notifications
      fprintf('Performing max fine axis reset\n')
      end
   case 'center'
      centertrue = true;
      if master.notifications
      fprintf('Performing center fine axis reset\n')
      end
      
   otherwise
      error("Second input of StageFineReset must be 'min', 'max', or 'center'")
end

%Check if stage is initialized
InitializationCheck('stage')

pause(.1)
if ax == 3
    master.stage.loc(ax) = coarseZControl.qPOS (axlist(ax));
    master.stage.loc(ax) = master.stage.loc(ax) * 1000;
else
    master.stage.loc(ax) = coarseXYControl.qPOS (axlist(ax));
    master.stage.loc(ax) = (-master.stage.loc(ax)) * 1000;
end

master.stage.loc(fax) = fineControl.qPOS (axlist(fax));

%Stores old total location
oldloc = master.stage.loc(fax) + master.stage.loc(ax);

%How far coarse and fine stages should move
%5 μm buffer added to min and max to prevent over-adjustments in future
%movements
if mintrue
   targ =  (master.stage.min(fax) + 10) - master.stage.loc(fax);
elseif maxtrue
   targ = (master.stage.max(fax) - 10) - master.stage.loc(fax);
elseif centertrue
   targ = master.stage.mid(fax) - master.stage.loc(fax);
end

%Moves fine stage by designated amount and moves coarse stage in the
%opposite direction to compensate
stageDirectMove("fine",axisString,targ)
stageDirectMove("coarse",axisString,-targ)

if ax == 3
    master.stage.loc(ax) = coarseZControl.qPOS (axlist(ax));
    master.stage.loc(ax) = master.stage.loc(ax) * 1000;
else
    master.stage.loc(ax) = coarseXYControl.qPOS (axlist(ax));
    master.stage.loc(ax) = (-master.stage.loc(ax)) * 1000;
end

master.stage.loc(fax) = fineControl.qPOS (axlist(fax));

%Checks if current location is within tolerance of the old location
stageToleranceCheck(axisString,oldloc)

end



