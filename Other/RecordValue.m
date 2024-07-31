function [outputValue] = RecordValue
%Records a single output value based on the experiment type

%Dependencies and inputs vary. Listed under each experiment type

%RecordValue v1.1 4/20/22

global master %#ok<*GVMIS> 

if ~isfield(master,'notifications'),      master.notifications = true;     end

%Checks if experiment type is present and one of possible values. If not,
%asks for user input
%Note: selection will expand as number of experiment types expands
while true
    if isfield(master,'expType')
        aa = master.expType;
        if isstring(aa)
            if aa == "sCMOS Ronchi" || aa == "sCMOS Spot Analysis" || aa == "NV NMR SPD" || aa == "GUI Optimization"
                break
            else
                if master.notifications
                fprintf("Experiment must be one of proffered types\n")
                end
            end
        else
            if master.notifications
            fprintf("Experiment type must be a string\n")
            end
        end
    end
        master.expType = input('Experiment type? "sCMOS Ronchi" "sCMOS Spot Analysis" "NV NMR SPD" "GUI Optimization"\n');
end

%Measures SNR of 2D FFT of a sCMOS image of a Ronchi ruling.
if master.expType == "sCMOS Ronchi"

    %Instrument dependencies:
    %Hamamatsu sCMOS camera

    %Code dependencies:
    %sCMOSInitialization
    %sCMOSImage

    %Inputs:
    %master.sCMOS.initialized : is stage initialized
    %master.sCMOS.framesper : number of frames to take per image
    %master.sCMOS.defect : in-built correction
    %master.sCMOS.hotPixel : what level of correction should be used.
    %Only relevant if master.sCMOS.defect == "on"
    %master.sCMOS.focradius : radius to look for signal value in FFT. 25 is
    %usually good for a Ronchi ruling

    %Takes image on sCMOS camera then performs 2D FFT
    [im,~] = sCMOSImage();
    ftim = abs(fftshift(fft2(im)));

    %Checks if focus radius is specified and if not, asks for user input
    while true
        if isfield(master.sCMOS, 'focradius')
            if  isscalar(master.sCMOS.focradius) && ~isstring(master.sCMOS.focradius)
                aa = master.sCMOS.focradius;
                if aa > 0 && aa <=100
                   break
                else
                    if master.notifications
                    fprintf("Focus radius must be between 1 and 100\n")
                    end
                end
            else
                if master.notifications
                fprintf("Number of steps must be a scalar\n")
                end
            end
        end
            master.sCMOS.focradius = input('Focus radius for 2D Fourier Transform? \n');
    end

    fr = master.sCMOS.focradius;%Abbreviation

    %Finds midpoint of fourier transformed image then creates a sub-image
    %based on focus radius
    midpoint = ceil((1+size(ftim))./2);
    ftimfoc = ftim(midpoint(1)-fr:midpoint(1)+fr, midpoint(2)-fr:midpoint(2)+fr);

    %Finds maximum of top and bottom half of the sub-image. this is the
    %signal value
    [~,topindex] = max(ftimfoc(1:fr,:), [], "all", "linear");
    [topr,topc] = ind2sub(size(ftimfoc(1:fr, :)), topindex);
    [~,botindex] = max(ftimfoc(fr+3:end, :), [], "all", "linear");
    [botr,botc] = ind2sub(size(ftimfoc(fr+3:end, :)), botindex);
    botr = botr + fr + 2;

    %Specifies signal and noise values based on location. noise is found at
    %high lateral frequency
    signal = (ftimfoc(topr, topc) + ftimfoc(botr, botc)) /2;
    noise = (ftim(midpoint(1), 1) + ftim(midpoint(1), end)) /2;
    SNR = signal ./ noise; %Signal to noise calculation

    outputValue = SNR;%Sets output of this function to be SNR

end

if master.expType == "sCMOS Spot Analysis"
    
    %Sets least squares analysis to suppress output message
    lsqoptions = optimset('display','off','MaxIter',100);
    
    %Takes image and stores old bounds
    [im,~] = sCMOSImage;
    oldxbounds = master.sCMOS.xbounds;
    oldybounds = master.sCMOS.ybounds;

    %Crops image if not already cropped
    if master.sCMOS.ih == master.sCMOS.iw && master.sCMOS.ih == 2304

        figure ('Name',"Uncropped Image",'NumberTitle',"off")
        imagesc(im)
        colormap(gray(256));
        colorbar
        title("Click image in 2 locations to select crop PSF area")
        [cols,rows] = ginput(2);
        close
        ybounds = sort(round(rows),"ascend");
        xbounds = sort(round(cols),"ascend");

        %Changes overall bounds to new crop
        master.sCMOS.xbounds = master.sCMOS.xbounds(1) + xbounds - 1;
        master.sCMOS.ybounds = master.sCMOS.ybounds(1) + ybounds - 1;

        cim = im(ybounds(1):ybounds(2),xbounds(1):xbounds(2));

    else
        cim = im;
    end
    
    %Checks to see if user is happy with cropped image
    if isfield(master,"readyCheck")
        if master.readyCheck
            while true
                figure ('Name',"Cropped Image",'NumberTitle',"off")
                imagesc(cim)
                colormap(gray(256));
                colorbar
                title("Cropped Image")
                
                psfiscorrect = input('Satisfied with PSF area? "no" "yes"\n');
                while true
                    aa = psfiscorrect;
                    if  isscalar(aa) && isstring(aa)                        
                        if aa == "no" || aa == "yes"
                            break
                        else
                            if master.notifications
                            fprintf('Answer must be "no" or "yes"\n')
                            end
                        end
                    else
                        if master.notifications
                        fprintf('Answer must be a string\n')
                        end
                    end
                    
                        psfiscorrect = input('Satisfied with PSF area? "no" "yes"\n');
                end          

                if psfiscorrect == "no"
                    
                    zoomdesire = input('Zoom in or out? "in" "out"\n');
                    while true
                        aa = zoomdesire;
                        if  isscalar(aa) && isstring(aa)
                            if aa == "in" || aa == "out"
                                break
                            else
                                if master.notifications
                                fprintf('Answer must be "in" or "out"\n')
                                end
                            end
                        else
                            if master.notifications
                            fprintf('Answer must be a string\n')
                            end
                        end
                        
                            zoomdesire = input('Zoom in or out? "in" "out"\n');
                    end
                
                    if zoomdesire == "out"
                        close
                        figure ('Name',"Uncropped Image",'NumberTitle',"off")
                        imagesc(im)
                        colormap(gray(256));
                        colorbar
                        title("Uncropped Image")
                    end
                    
                    if master.notifications
                    fprintf("Click 2 locations to reselect crop PSF area\n")
                    end
                    title("Click image in 2 locations to select crop PSF area")
                    [cols,rows] = ginput(2);
                    close
                    ybounds = sort(round(rows),"ascend");
                    xbounds = sort(round(cols),"ascend");

                    if zoomdesire == "out"
                        %revert cropped bounds to original bounds
                        master.sCMOS.xbounds = oldxbounds;
                        master.sCMOS.ybounds = oldybounds;
                    end

                    master.sCMOS.xbounds = master.sCMOS.xbounds(1) + xbounds - 1;
                    master.sCMOS.ybounds = master.sCMOS.ybounds(1) + ybounds - 1;

                    if zoomdesire == "in"
                        %changes cropped image to new bounds
                        cim = cim(ybounds(1):ybounds(2),xbounds(1):xbounds(2));
                    else
                        %changes original image to new bounds
                        cim = im(ybounds(1):ybounds(2),xbounds(1):xbounds(2));
                    end
                    
                else
                    break

                end%end changing bounds
            end%end while
                       
        end
    end%End check
    
    if isfield(master.stage,'ax')
        if master.stage.ax == "z"
            %looks only at the 5 brightest pixels 
            maxbrights = sort(reshape(cim,[1 size(cim,1)*size(cim,2)]),'descend');
            outputValue(1) = mean(maxbrights(1:5));
        elseif master.stage.ax == "x" || master.stage.ax == "y"
            %Main output is just the mean of the PSF
            outputValue(1) = mean(cim,"all");
        end
    else
        %Main output is just the mean of the PSF
        outputValue(1) = mean(cim,"all");
    end
     
    if isfield(master.sCMOS,'PSFlog'),    master.sCMOS.PSFlog(:,:,end+1) = cim;
    else,      master.sCMOS.PSFlog = cim;
    end
    
    if isfield(master.sCMOS,'PSFmeanlog'),      master.sCMOS.PSFmeanlog(end+1) = outputValue(1);
    else,      master.sCMOS.PSFmeanlog = outputValue(1);
    end

    [xgrid,ygrid] = meshgrid(1:size(cim,2),1:size(cim,1));
    bgguess = prctile(cim,10,'all');%tenth percentile is considered background
    ampguess = max(cim,[],'all') - bgguess;
    yguess = ceil((1+size(cim,1)) / 2); %center of image is estimated location
    xguess = ceil((1+size(cim,2)) / 2);

    master.sCMOS.xwaist = sqrt(2) * size(cim,2);
    master.sCMOS.ywaist = sqrt(2) * size(cim,1);
    xwaist = master.sCMOS.xwaist;
    ywaist = master.sCMOS.ywaist;

    %creates "wall" of the size of the input grid that is exponentially
    %decaying according to the decay rate. Center of the decay is determined by
    %loc input
    locgrid = @(loc,waist,axisgrid) exp(-( (axisgrid - loc).^2) /(waist^2));

    %Creates function that calculates difference between "image" created by
    %locations and decays inputs and the actual image
    totalfun = @(coeff,xloc,xwaist,yloc,ywaist,background) ...
        (coeff .* locgrid(xloc,xwaist,xgrid) .* locgrid(yloc,ywaist,ygrid)) ...
        + background - cim;

    %Takes previous function and turns it into a function with a single
    %input variable
    parametersfun = @(parameters) totalfun(parameters(1),parameters(2),...
        parameters(3),parameters(4),parameters(5),parameters(6));
    
    if ~isfield(master.sCMOS,'passlog'),     master.sCMOS.passlog = [];    end
    
    if ~isfield(master.sCMOS,'modellog'),    master.sCMOS.modellog = [];      end

    try %Outputs 2-4 of model amplitude, x distance, and y distance obtained here
        %Performs nonlinear least squares analysis to minimize the sum across
        %the image of the absolute value of (model - image). The output
        %parameters are the resultant best fit model
        %parameter 1: maximum amplitude
        %parameter 2: x coordinate (column) of the center of the point source
        %parameter 3: width of the source AKA waist along x dimension
        %parameter 4: y coordinate (row) of the center of the point source
        %parameter 5: height of the source AKA waist along y dimension
        %parameter 6: background intensity
        outputparameters = lsqnonlin(parametersfun,...
            [ampguess,xguess,xwaist,yguess,ywaist,bgguess],...
            [],[],lsqoptions);

        %If a positive amplitude is obtained from this model
        if outputparameters(1) > 0
            
            %Outputs amplitude as 2nd output
            outputValue(2) = outputparameters(1);
            
            %Output distance to center for x and y as 3rd and 4th output
            outputValue(3) = outputparameters(2) - (1+ size(cim,2))/2;
            outputValue(4) = outputparameters(4) - (1+ size(cim,1))/2;
            
            master.sCMOS.passlog(end+1) = 1;            
        else
            if master.notifications
                fprintf('Negative amplitude for spot model obtained. Setting output values 2:4 to low number\n')
            end
            outputValue(2:4) = -1E9;
            master.sCMOS.passlog(end+1) = 0;
        end       
        
        %Saves output parameters regardless of whether model succeeded
        master.sCMOS.modellog(end+1,:) = outputparameters;
        
    catch                
        if master.notifications
            fprintf('Could not complete least squares analysis. Setting output values 2:4 to low number.\n')
        end
        outputValue(2:4) = -1E9;
        master.sCMOS.passlog(end+1) = 0;
        %Duplicates previous model
        master.sCMOS.modellog(end+1,:) = [0,0,0,0];
    end
    
    %Zooms out by 50 pixels in all directions then takes image.
    %results will correspond to same log number as the PSF log
    master.sCMOS.xbounds(1) = master.sCMOS.xbounds(1) - 50;
    master.sCMOS.xbounds(2) = master.sCMOS.xbounds(2) + 50;
    master.sCMOS.ybounds(1) = master.sCMOS.ybounds(1) - 50;
    master.sCMOS.ybounds(2) = master.sCMOS.ybounds(2) + 50;
    [im,~] = sCMOSImage();
    
    if isfield(master.sCMOS,'bigimlog'),     master.sCMOS.bigimlog(:,:,end+1) = im;
    else,      master.sCMOS.bigimlog = im;
    end
    
    master.sCMOS.xbounds(1) = master.sCMOS.xbounds(1) + 50;
    master.sCMOS.xbounds(2) = master.sCMOS.xbounds(2) - 50;
    master.sCMOS.ybounds(1) = master.sCMOS.ybounds(1) + 50;
    master.sCMOS.ybounds(2) = master.sCMOS.ybounds(2) - 50;

end


if master.expType == "NV NMR SPD"
    
    global NIDAQ  %#ok<TLEV>
    
    %Stores current sequence to be retrieved later
    if isfield(master.PB,'sequence'),     oldseq = master.PB.sequence;    end


    
    %Initializes NIDAQ if not already done, otherwise stores current values
    %for retrieval later
    if isfield(master,'NIDAQ')
        if isfield(master.NIDAQ,'initialized')
            if master.NIDAQ.initialized
                if ~any(master.NIDAQ.channel == "ctr3")
                    master.NIDAQ.channel(end+1) = "ctr3";
                    master.NIDAQ.counttype(end+1) = "EdgeCount";
                    addinput(NIDAQ, "Dev1", master.NIDAQ.channel(end), master.NIDAQ.counttype(end))
                end
                %If "ctr3" is already a channel, do nothing
            else
                master.NIDAQ.channel(1) = "ctr3";
                master.NIDAQ.counttype(1) = "EdgeCount";
                master.NIDAQ.maxrate = 1.25e6;                
                NIDAQInitialization
            end
        end
    end
    
    %Sets default duration of recording data
    if ~isfield(master.NIDAQ,'recordduration'),    master.NIDAQ.recordduration = 1e6;     end
        
    %The folllowing is the basic sequence to record counts for a duration
    
    master.PB.command.address = 1;
    master.PB.command.output = "3";
    master.PB.command.direction = 'CONTINUE';
    master.PB.command.duration = master.NIDAQ.recordduration;
    PBAddSequence
    
    master.PB.command.address = 2;
    master.PB.command.output = "0";
    master.PB.command.direction = 'CONTINUE';
    master.PB.command.duration = 100;
    PBAddSequence

    master.PB.command.address = 3;
    master.PB.command.output = "0";
    master.PB.command.direction = 'STOP';
    master.PB.command.duration = 100;
    PBAddSequence
    
    PBFinalize
    
    pause(.001) %Allows instrumentation to catch up to MatLab
        
    % Resetting DAQ counts
    resetcounters(NIDAQ);
    
    % Pulse Blaster
    PBRun
    
    % Readout DAQ counts
    daqout = read(NIDAQ);
    outputValue =  daqout.Dev1_ctr3;
    clear daqout
    
    %Retrieves old sequence and inputs that back into PB if old sequence
    %exists
    if exist('oldseq','var')          
        master.PB.sequence = oldseq;
        PBFinalize
    end
    
end


if master.expType == "GUI Optimization"
   %store old pulse sequence
   %make new pulse sequence checking raw number of counts
   %run pulse sequence and output counts or contrast
    
%     if isfield(master.PB,'sequence')
%         %Stores current sequence to be retrieved later
%         oldseq = master.PB.sequence;
%         master.PB = rmfield(master.PB,'sequence');
%     end
    
%     if isfield(master.PB,'sequenceDuration')
%       oldDur = master.PB.sequenceDuration;
%     end
    
%     InitializationCheck('NIDAQ')
    
%     oldClock = master.NIDAQ.useClock;    
%     oldSettle = master.stage.ignoreWait;
%     oldInt = master.PB.useInterpreter;
%     
%     master.stage.ignoreWait = false;
    
    % Pulse Blaster
    [sig, ref] = PBRun;

    % Readout DAQ counts
    if master.gui.optparam == "contrast" 
       outputValue = ref - sig;
    else %Ref or sig will both output to ref due to not using the clock
       outputValue =  ref;       
    end
    
    %Turn into counts per second
    outputValue = outputValue / (master.gui.optdur*1e-9);
    
%     master.PB.useInterpreter = oldInt;
%     master.stage.ignoreWait = oldSettle;
%     master.NIDAQ.useClock = oldClock;
    
%     if exist('oldDur','var')
%       master.PB.sequenceDuration = oldDur;
%     end

    %Retrieves old sequence and inputs that back into PB if old sequence
    %exists
%     if exist('oldseq','var')     
%         master.PB.sequence = oldseq;
%         PBFinalize
%     end

end



end


