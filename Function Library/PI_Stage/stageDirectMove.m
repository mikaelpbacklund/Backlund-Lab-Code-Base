function stageDirectMove(fineOrCoarse,axisString,targetMovement)
%Simplified movement function that does not take into account stage
%boundaries or tolerance
%distanceToMove input units is micrometers

%Instrument dependencies:
%Coarse XY, coarse Z, and fine XYZ controllers from PI

%Code dependencies:
%InitializationCheck
%stageInitialization

%stageDirectMove v1.1 4/19/22

global coarseZControl %#ok<*GVMIS> 
global coarseXYControl
global fineControl
global master

%Abbreviations
axlist = master.stage.axes;
targ = targetMovement;

%Checks to see if inputs are correct

switch fineOrCoarse
   
   case 'fine'
      fineaxis = true;
   case 'coarse'
      fineaxis = false;
      
   otherwise
      error("First input of stageDirectMove must be either 'fine' or 'coarse'")
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
      error("Second input of stageDirectMove must be 'x', 'y', or 'z'")
end
fax = ax+3;%Fine axis tag

if ~isa(targ,'double') || ~isscalar(targ)
   error("Third input of stageDirectMove must be scalar double")
end

%Check if stage is initialized
InitializationCheck('stage')

if fineaxis
   fineControl.MVR ( axlist(fax) , targ );
   if master.notifications
      fprintf('Moving %s %s %.2f μm\n',fineOrCoarse,axisString,targ)
   end
   pause(master.stage.finepause)
elseif ax == 3 %z axis
   coarseZControl.MVR (axlist(ax) , (targ)/1000);
   if master.notifications
      fprintf('Moving %s %s %.2f μm\n',fineOrCoarse,axisString,targ)
   end
   pause(master.stage.coarsepause)
else
   coarseXYControl.MVR (axlist(ax) , -targ/1000);
   if master.notifications
      fprintf('Moving %s %s %.2f μm\n',fineOrCoarse,axisString,targ)
   end
   pause(master.stage.coarsepause)
end

n = 0;
while true
    if master.stage.ignoreWait
        break
    end
   %End loop if no longer reporting movement
   if fineaxis
      if ~fineControl.IsMoving(axlist(fax))
         break
      end
   elseif ax == 3
      if ~coarseZControl.IsMoving(axlist(ax))
         break
      end
   else
      if ~coarseXYControl.IsMoving(axlist(ax))
         break
      end
   end
   
   pause(.001)
   
   %Counter to ensure stage does not get "stuck"
   n = n+1;
   if n == 250 && fineaxis || n == 1000 && ~fineaxis
      if master.notifications
         fprintf('%s %s stage not reporting finished movement after %d second(s). Halting movement\n',fineOrCoarse,axisString,n/1000)
      end
      if fineaxis
          fineControl.HLT(axlist(fax))
      elseif ax == 3
          coarseZControl.HLT(axlist(ax))
      else
          coarseZControl.HLT(axlist(ax))
      end
      pause(.001)
      break
   end
   
end

if fineaxis
    master.stage.loc(fax) = fineControl.qPOS (axlist(fax));
elseif ax == 3 
    currpos = coarseZControl.qPOS (axlist(ax));
    master.stage.loc(ax) = currpos*1000;
else
    currpos = coarseXYControl.qPOS (axlist(ax));
    master.stage.loc(ax) = -currpos*1000;
end

%Adds current location to record
master.stage.locrecord(end+1,:) = master.stage.loc;

end

