function stageRelativeMove(axisString,targetMovement)
%Moves axis by target distance in micrometers relative to current position

%Instrument dependencies:
%Coarse XY, coarse Z, and fine XYZ controllers from PI

%Code dependencies:
%InitializationCheck
%stageInitialization
%stageDirectMove
%stageFineReset
%stageToleranceCheck

%stageRelativeMove v2.0 4/19/22

global master
global coarseXYControl
global coarseZControl
global fineControl

%Abbreviation
targ = targetMovement;

switch axisString
   
   case 'x'
      ax = 1;%Numerical tag of axis
   case 'y'
      ax = 2;      
   case 'z'
      ax = 3;
      
   otherwise
      error("First input of stageRelativeMove must be 'x', 'y', or 'z'")
end
fax = ax+3;%Fine axis tag

if ~isa(targ,'double') || ~isscalar(targ)
   error("Second input of stageRelativeMove must be scalar double")
end

%Check if stage is initialized
InitializationCheck('stage')

if ax == 3
    master.stage.loc(ax) = coarseZControl.qPOS (master.stage.axes(ax));
    master.stage.loc(ax) = master.stage.loc(ax) * 1000;
else
    master.stage.loc(ax) = coarseXYControl.qPOS (master.stage.axes(ax));
    master.stage.loc(ax) = (-master.stage.loc(ax)) * 1000;
end

master.stage.loc(fax) = fineControl.qPOS (master.stage.axes(fax));

%Abbreviations for being inside fine bounds
inboundpos = targ > 0 && (targ + master.stage.loc(fax)) <= master.stage.max(fax);
inboundneg = targ < 0 && (master.stage.loc(fax) + targ) >= master.stage.min(fax);

if targ == 0
   %Do nothing
   
   %If target is not outside of fine bounds, enact move on fine controller
elseif inboundpos || inboundneg
   
   stageDirectMove("fine",axisString,targ)
   
else
   %If target is outside of fine bounds, reset fine to midpoint, move coarse
   %to desired location, then tune using fine
   
   
   %Stores absolute target for use in tolerance check
   absolutetarg = targ + master.stage.loc(fax) + master.stage.loc(ax);
   
   if master.stage.doReset
       %Move stage to min/max if target is positive/negative to allow for more
       %consecutive movements without a reset
       if targ >  0
           stageFineReset(axisString,'min')
       else
           stageFineReset(axisString,'max')
       end
   end
   
   %Ensures coarse stage does not overshoot boundary
   if targ+ master.stage.loc(ax)> master.stage.max(ax) || master.stage.loc(ax) + targ < master.stage.min(ax)
      error('Coarse %s stage boundary reached\n',axisString)
   end

   %Move fine stage to target
   stageDirectMove("coarse",axisString,targ)
   
   %Checks if current location is within tolerance of the absolute target
   stageToleranceCheck(axisString,absolutetarg)

end

end


