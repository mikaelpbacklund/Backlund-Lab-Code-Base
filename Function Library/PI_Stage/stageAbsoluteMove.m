function stageAbsoluteMove(axisString,targetLocation)
%Moves to absolute location in micrometers for a specific axis

%Instrument dependencies:
%Coarse XY, coarse Z, and fine XYZ controllers from PI

%Code dependencies:
%InitializationCheck
%stageInitialization
%stageDirectMove
%stageFineReset
%stageToleranceCheck
%stageRelativeMove

%stageAbsoluteMove v2.0 4/19/22

global master
global coarseZControl %#ok<*GVMIS> 
global coarseXYControl
global fineControl

targ = targetLocation;

switch axisString
   
   %Numerical tag of axis
   case 'x'
      ax = 1;
   case 'y'
      ax = 2;
   case 'z'
      ax = 3;
      
   otherwise
      error("First input of stageAbsoluteMove must be 'x', 'y', or 'z'")
end
fax = ax+3;%Fine axis tag

if ~isa(targ,'double') || ~isscalar(targ)
   error("Second input of stageAbsoluteMove must be scalar double")
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

%Finds difference between current combined location and the target
combloc = master.stage.loc(ax) + master.stage.loc(fax);
reltarg= targ - combloc;

%Uses relative move code instead of direct commands to minimize change in
%coarse axes. This effectively allows the script to be coarse/fine agnostic
stageRelativeMove(axisString,reltarg)

if master.stage.ignoreWait
    pause(abs(reltarg)/3000)
end

if ax == 3
    master.stage.loc(ax) = coarseZControl.qPOS (master.stage.axes(ax));
    master.stage.loc(ax) = master.stage.loc(ax) * 1000;
else
    master.stage.loc(ax) = coarseXYControl.qPOS (master.stage.axes(ax));
    master.stage.loc(ax) = (-master.stage.loc(ax)) * 1000;
end

master.stage.loc(fax) = fineControl.qPOS (master.stage.axes(fax));

if master.notifications
   fprintf("%s axis moved to %.2f micrometers\n",axisString,master.stage.loc(ax)+master.stage.loc(fax))
end



end









