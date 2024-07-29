function stageOptimization
%Optimizes currently chosen experimental parameter by adjusting stage
%position. Used to correct for stage drift over time.

%Instrument dependencies:
%Coarse XY, coarse Z, and fine XYZ controllers from PI
%Instrument(s) used in RecordValue

%Code dependencies: 
%InitializationCheck
%stageInitialization
%stageDirectMove
%stageFineReset
%stageToleranceCheck
%stageRelativeMove
%RecordValue and its dependencies

%stageOptimization v2.1 6/8/22

global master 

InitializationCheck('stage')

if ~isfield(master.stage,'opttype')
   master.stage.opttype = "Raw Value";
elseif master.stage.opttype ~= "Raw Value" && master.stage.opttype ~= "Gaussian Peak"
   error('master.stage.opttype must be either "Raw Value" or "Gaussian Peak"')
end

if strcmp(master.expType,"GUI Optimization")    
    %Stores current sequence to be retrieved later
    if isfield(master.PB,'sequence'),     oldseq = master.PB.sequence;    end

    if isfield(master.PB,'sequenceDuration')
      oldDur = master.PB.sequenceDuration;
    end

    InitializationCheck('NIDAQ')
    
    oldClock = master.NIDAQ.useClock;    
    oldSettle = master.stage.ignoreWait;
    oldInt = master.PB.useInterpreter;


    
    master.stage.ignoreWait = false;
    
    if master.gui.optparam == "RF off"
       master.NIDAQ.useClock = false;
       
       master.PB.command.output = 1;
       master.PB.command.direction = 'CONTINUE';
       master.PB.command.duration = 20;
       PBAddSequence
       
       master.PB.command.output = 3;
       master.PB.command.direction = 'CONTINUE';
       master.PB.command.duration = round(master.gui.optdur);
       PBAddSequence
       
    elseif master.gui.optparam == "RF on"
       master.NIDAQ.useClock = false;
       %This allows RF and DAQ to react before beginning counting
       master.PB.command.output = 9;
       master.PB.command.direction = 'CONTINUE';
       master.PB.command.duration = 20;
       PBAddSequence
       
       %Turn on RF, DAQ switch to ctr1, and laser and record counts
       master.PB.command.output = 11;
       master.PB.command.direction = 'CONTINUE';
       master.PB.command.duration = round(master.gui.optdur);
       PBAddSequence
       
    else %contrast
       master.NIDAQ.useClock = true;
       master.PB.command.output = 1;
       master.PB.command.direction = 'CONTINUE';
       master.PB.command.duration = 20;
       PBAddSequence
       
       master.PB.command.output = 3;
       master.PB.command.direction = 'CONTINUE';
       master.PB.command.duration = round(master.gui.optdur);
       PBAddSequence

       master.PB.command.output = 13;
       master.PB.command.direction = 'CONTINUE';
       master.PB.command.duration = 20;
       PBAddSequence
       
       master.PB.command.output = 15;
       master.PB.command.direction = 'CONTINUE';
       master.PB.command.duration = round(master.gui.optdur);
       PBAddSequence
    end    
    
    master.PB.command.output = 0;
    master.PB.command.direction = 'CONTINUE';
    master.PB.command.duration = 100;
    PBAddSequence

    master.PB.command.output = 0;
    master.PB.command.direction = 'STOP';
    master.PB.command.duration = 100;
    PBAddSequence

    cumdur = sum([master.PB.sequence.duration]);
    
    master.PB.sequenceDuration = cumdur;
    
    master.PB.useInterpreter = false;

    PBFinalize

end


%Parent loop checks radius, sequence, and steps vectors are same length
while true
    
    %If sequence is not already present or vector or has members besides 1,
    %2, and 3, requests user input
    while true
        if ( isscalar(master.stage.sequence) || isvector(master.stage.sequence) ) && isstring(master.stage.sequence)
            if all(ismember(master.stage.sequence,["x" "y" "z"]))
                break
            else
                fprintf('Sequence must only contain "x", "y", or "z"\n')
            end
        elseif isempty(master.stage.sequence)
            %do nothing
        else
            fprintf("Sequence must be string vector\n")
        end
            master.stage.sequence = input('Sequence vector? "x" "y" "z". Format ["axis" "axis" ...]\n');
    end
    
    %If radius is not already present or vector requests user input
    while true
        if ( isscalar(master.stage.radius) || isvector(master.stage.radius) ) && ~isstring(master.stage.radius)
            break      
        elseif isempty(master.stage.radius)
            %do nothing
        else
            fprintf("Radius must be vector\n")
        end
            master.stage.radius = input('Radius vector (μm)? Format [# # #...]\n');
    end

    %If steps is not already present or vector or has a member not
    %between 1 and 100, requests user input
    while true
        if ( isscalar(master.stage.steps) || isvector(master.stage.steps) ) && ~isstring(master.stage.steps)
            if all(mod(master.stage.steps,2))
                if all([all(master.stage.steps > 0) all(master.stage.steps < 100 )])
                    break
                else
                    fprintf("Number of steps must be between 1 and 100\n")
                end
            else
                fprintf("Number of steps must be odd\n")
            end
        elseif isempty(master.stage.steps)
            %do nothing
        else
            fprintf("Number of steps must be vector\n")
        end
            master.stage.steps = input('Number of optimization steps? Format [# # #...]\n');
    end
    
    %If length of all three above settings is not equal, ask for input on
    %all 3 settings then repeat error check
    if length(master.stage.sequence) == length(master.stage.radius) && length(master.stage.sequence) == length(master.stage.steps)
        break
    else
        fprintf('Radius, sequence, and steps vectors must be the same length\n')
        master.stage.sequence = input('Sequence vector? "x" "y" "z". Format ["axis" "axis" ...]\n');
        master.stage.radius = input('Radius vector (μm)?\n');
        master.stage.steps = input('Number of optimization steps?\n');
    end
    
end %end parent loop for checking length equivalency

%Counter of the number of sequences
if ~isfield(master.stage,'optcounter')
   master.stage.optcounter = 0;
end
master.stage.optcounter = master.stage.optcounter + 1;

if strcmp(master.stage.opttype,"Alternating")
   if mod(master.stage.optcounter,2) == 0
      opttype = "Raw Value";
   else
      opttype = "Gaussian Peak";
   end
else
   opttype = master.stage.opttype;
end

for ii = 1:length(master.stage.sequence)   
    
    %Record of the values obtained during this optimization procedure.
    %Keeps a permanent log until master is reset
    if ~isfield(master.stage,'valrecord')
        master.stage.valrecord = [];
    end
    
    %Creates evenly spaced vector based on radius given and number of steps
    optvector = linspace(-master.stage.radius(ii),master.stage.radius(ii),master.stage.steps(ii));
    %Rounds vector to decimal places usable by controllers
    optvector = round(optvector,2);

    %Resets current record for this part of the sequence
    currentrecord = [];
    
    %Moves stage and takes values in accordance with the specifications of
    %this part of the sequence
    for jj = 1:master.stage.steps(ii)
        if jj == 1
            currtarg = optvector(1);%Sets target to minimum value of vector steps
        else
            %Sets target to value one step higher than previous
            currtarg = optvector(jj) - optvector(jj-1);
        end
        
        stageRelativeMove(master.stage.sequence(ii),currtarg)%Moves to target
        
        %Records value for comparison at the end of the loop
        %Only the first column is actually read out as the parameter of
        %interest. other columns can be used to store other data
        %Row indicates which optimization sequence the record represents
        currentrecord = [currentrecord;RecordValue]; %#ok<AGROW> 
    end

    %The following section adds the values obtained for this part of the
    %sequence to the total record of values. if the arrays are of
    %incompatible sizes, it adds zeros to make them compatible
    cval = currentrecord;
    rsize = size(master.stage.valrecord);
    csize = size(cval);
    if length(rsize) ~= 3
        rsize(3) = 1;
    end

    if csize(1) > rsize(2)
        master.stage.valrecord(:,rsize(2)+1:csize(1),:) = zeros(rsize(1),csize(1)-rsize(2),rsize(3));
    elseif csize(1) < rsize(2)
        cval(csize(1)+1:rsize(2),:) = zeros(rsize(2)-csize(1),csize(2));
    end

    csize = size(cval);
    rsize = size(master.stage.valrecord);
    if length(rsize) ~= 3
        rsize(3) = 1;
    end

    if csize(2) > rsize(3)
        master.stage.valrecord(:,:,rsize(3)+1:csize(2)) = zeros(rsize(1),rsize(2),csize(2)-rsize(3));
    elseif csize(2) < rsize(3)
        cval(:,csize(2)+1:rsize(3)) = zeros(csize(1),rsize(3)-csize(2));
    end

    %Adds the current record to the log
    master.stage.valrecord(end+1,:,:) = cval; 
    
    if all(currentrecord(1) == currentrecord) %If all values are equal to the first
       if master.notifications 
          fprintf('All values equivalent for optimization step %d. Returning to starting location',ii)
       end
       stageRelativeMove(master.stage.sequence(ii),median(optvector) - optvector(end))
    
    elseif strcmp(opttype,"Raw Value")
       %Find max value returned from value recording
       master.stage.best = find(max(currentrecord(:,1)) == currentrecord(:,1));
       %Subtracts highest step to return to original value then changes target to best location
       stageRelativeMove(master.stage.sequence(ii),optvector(master.stage.best(1)) - optvector(end))
       

    elseif strcmp(opttype,"Gaussian Peak")
       
       axisvec = 1:length(optvector);
       fy = currentrecord(:,1);
       
       try
         f1 = fit(axisvec.',fy,'gauss1');
         f1fail = false;
       catch
          f1fail = true;
       end
       try
         f2 = fit(axisvec.',fy,'gauss2');
         f2fail = false;
       catch
          f2fail = true;
       end
       
       if ~f1fail
          fcoeffs = coeffvalues(f1);
          famps = fcoeffs(1:3:end);
          fcenters = fcoeffs(2:3:end);
          fwidths = fcoeffs(3:3:end);
          
          validmin =  famps > min(fy) * .1;
          validmax =  famps < max(fy) * 100;
          validamps = all([validmin;validmax],1);
          
          validmin =  fcenters > -0.5*length(axisvec);
          validmax =  fcenters < 1.5*length(axisvec);
          validcenters = all([validmin;validmax],1);
          
          validmin =  fwidths > 1;
          validmax =  fwidths < length(axisvec);
          validwidths = all([validmin;validmax],1);
          
          widthcenter = any([validcenters;validwidths],1);
          totalvalid = all([validamps;widthcenter],1);          
          nvalid = sum(totalvalid);
          
          if nvalid ~= 0
             if nvalid == 1
                f1cen = fcenters(totalvalid);
             else
                amporder = sort(famps(totalvalid));
                if amporder(1) > 2*amporder(2) %Amplitude difference is high, choose highest amp
                   f1cen = fcenters(amporder(1) == famps);
                else %amp difference is low, choose lowest width
                   f1cen = fcenters(min(fwidths) == fwidths);
                end
             end
          else %nothing is valid so default back to center
             f1cen = median(axisvec);
             f1fail = true;
          end
          
       else
          f1cen = median(axisvec);
       end
       
        if ~f2fail
          fcoeffs = coeffvalues(f2);
          famps = fcoeffs(1:3:end);
          fcenters = fcoeffs(2:3:end);
          fwidths = fcoeffs(3:3:end);
          
          validmin =  famps > min(fy) * .1;
          validmax =  famps < max(fy) * 100;
          validamps = all([validmin;validmax],1);
          
          validmin =  fcenters > -0.5*length(axisvec);
          validmax =  fcenters < 1.5*length(axisvec);
          validcenters = all([validmin;validmax],1);
          
          validmin =  fwidths > 1;
          validmax =  fwidths < length(axisvec);
          validwidths = all([validmin;validmax],1);
          
          widthcenter = any([validcenters;validwidths],1);
          totalvalid = all([validamps;widthcenter],1);          
          nvalid = sum(totalvalid);
          
          if nvalid ~= 0
             if nvalid == 1
                f2cen = fcenters(totalvalid);
             else
                amporder = sort(famps(totalvalid));
                if amporder(1) > 2*amporder(2) %Amplitude difference is high, choose highest amp
                   f2cen = fcenters(amporder(1) == famps);
                else %amp difference is low, choose lowest width
                   f2cen = fcenters(min(fwidths) == fwidths);
                end
             end
          else %nothing is valid so default back to center
             f2cen = median(axisvec);
             f2fail = true;
          end
          
       else
          f2cen = median(axisvec);
        end
       
       if ~f1fail
          if abs(f2cen - f1cen) < length(axisvec)/3
             finalanswer = f2cen;
          else
             if abs(f1cen-median(axisvec)) < abs(f2cen-median(axisvec))
                finalanswer = f1cen;
             else
                finalanswer = f2cen;
             end
          end  
       elseif ~f2fail
          finalanswer = f2cen;         
       else
          finalanswer = median(axisvec);
       end       
       %Finds center of model in real numbers
       truecenter = ((master.stage.radius(ii)*2)/master.stage.steps(ii))*finalanswer;
       
       %Moves stage to center of model from the end
       stageRelativeMove(master.stage.sequence(ii),truecenter-(master.stage.radius(ii)*2))
       
    end
    
    %If optimization logging is enabled, records current value and location
    if master.stage.recordOptVal
       
       if ~isfield(master.stage,'optvallog')
          master.stage.optvallog = RecordValue;
       else
          master.stage.optvallog(end+1,:) = RecordValue;
       end
    end
       
    if master.stage.recordOptLoc
       if ~isfield(master.stage,'optloclog')
          master.stage.optloclog = master.stage.loc;
       else
          master.stage.optloclog(end+1,:) = master.stage.loc;
       end
    end
    

end %Ends sequence loop



if exist('oldDur','var')
    master.PB.sequenceDuration = oldDur;
end
master.PB.useInterpreter = oldInt;
master.stage.ignoreWait = oldSettle;
master.NIDAQ.useClock = oldClock;

if exist('oldseq','var')
    master.PB.sequence = oldseq;
    PBFinalize
end

%     if strcmp(master.comp,'NV')
%     [~,r] = PBRun;
%     fprintf('testing counts end: %d\n',r)
%     end

fprintf('Stage optimization complete\n')

end



