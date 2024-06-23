function [] = sCMOSCalImage()
%Takes image(s) using the Hamamatsu camera. Output is 3D unit16 where 3rd
%dimension is for frame number.

%Instrument dependencies:
%Hamamatsu sCMOS camera

%Code dependencies:
%sCMOSInitialization

%%Error checks

global hamm %#ok<*GVMIS>
global master
global hammsource

if ~isfield(master,'notifications')
    master.notifications =true;
end

iscorrect = true;
if isfield(master,'sCMOS')
    if isfield(master.sCMOS,'initialized')
        if isscalar(master.sCMOS.initialized) && ~isstring(master.sCMOS.initialized)
            if master.sCMOS.initialized
                iscorrect = true;
            end
        end
    end
end
if ~iscorrect
    if ~isfield(master.notifications)
        fprintf('sCMOS not initialized. Beginning intialization');
    end
    sCMOSInitialization()
end

%% Main body

if master.sCMOS.hotPixel == "all"
    hotrepeat = 3;
else
    hotrepeat = 1;
end

hamm.LoggingMode = 'memory';


%Frames taken in sets of 100 to not overload memory
nsets = ceil(master.sCMOS.framesper /100);
lastset = mod(master.sCMOS.framesper,nsets);
if lastset == 0
    lastset = 100;%if no remainder, set last set number of frames to 100
end

ii = 0;
iscorrect = false;
while ~iscorrect

    ii = ii+1;


    for kk = 1:hotrepeat

        if (master.sCMOS.hotPixel == "all" && kk == 1) || master.sCMOS.hotPixel == "minimum"
            meantitle = append(append('Level ',append(num2str(ii-1),' Mean')),' (Minimum)');
            hammsource.HotPixelCorrectionLevel = "minimum";
        elseif (master.sCMOS.hotPixel == "all" && kk == 2) || master.sCMOS.hotPixel == "standard"
            meantitle = append(append('Level ',append(num2str(ii-1),' Mean')),' (Standard)');
            hammsource.HotPixelCorrectionLevel = "standard";
        elseif (master.sCMOS.hotPixel == "all" && kk == 3) || master.sCMOS.hotPixel == "aggressive"
            meantitle = append(append('Level ',append(num2str(ii-1),' Mean')),' (Aggressive)');
            hammsource.HotPixelCorrectionLevel = "aggressive";
        end

        hamm.FramesPerTrigger = 100;

        levelMean = zeros(master.sCMOS.ih,master.sCMOS.iw);
        levelSqMean = zeros(master.sCMOS.ih,master.sCMOS.iw);

        for jj = 1:nsets

            %for the final set, change frames to left over value
            if jj == nsets
                hamm.FramesPerTrigger = lastset;
            end

            start(hamm)

            %continues acquiring until all frames are available
            if jj ~= nsets || lastset == 0
                while get(hamm,'FramesAvailable')<100
                    pause(.25)
                end
                if master.notifications
                    fprintf('%d / %d frames complete',jj*100,master.sCMOS.framesper)
                end
            else
                while get(hamm,'FramesAvailable')<lastset
                    pause(.25)
                end
                fprintf('%d / %d frames complete',master.sCMOS.framesper,master.sCMOS.framesper)
            end

            imageOut = getdata(hamm);
            stop(hamm)
            %Converts to 3D array. unsure why a 4th is created in the first place
            imageOut = squeeze(imageOut(master.sCMOS.ybounds(1):master.sCMOS.ybounds(2),...
                master.sCMOS.xbounds(1):master.sCMOS.xbounds(2),:,1));

            levelMean = levelMean + sum(squeeze(imageOut),3);
            levelSqMean = levelSqMean + sum(squeeze(imageOut).^2,3);

        end %end nsets

        levelMean = levelMean ./ master.sCMOS.framesper;
        levelSqMean = levelSqMean ./ master.sCMOS.framesper;

        if ii == 1
            master.sCMOS.darkmean(:,:,kk) = levelMean;
            master.sCMOS.darksqmean(:,:,kk) = levelSqMean;
        else
            master.sCMOS.calmeans(:,:,ii-1,kk) = levelMean;
            master.sCMOS.calsqmeans(:,:,ii-1,kk) = levelSqMean;
        end

        if master.sCMOS.plots.mean == 1

            figure ('Name',meantitle,'NumberTitle',"off")
            imagesc(levelMean)
            colormap(gray(256));
            colorbar
            aa=colorbar;
            ylabel(aa,'Counts','FontSize',13,'Rotation',270,"FontWeight","normal");
            aa.Label.Position(1) = 3.3;
            title(meantitle)
            if master.sCMOS.plots.save
                saveas(gcf,append(meantitle,'.tif'))
            end
        end

        if hotrepeat ~= 1
            if master.notifications
                fprintf('Hot pixel setting %d complete. Mean pixel value = %.2f',kk,mean(levelMean,"all"))
            end
        end

    end %end hot pixel repeat

    if hotrepeat ~= 1
        if master.notifications
            fprintf('Brightness level %d complete',ii-1)
        end
    else
        if master.notifications
            fprintf('Brightness level %d complete. Mean pixel value = %.2f',ii-1,mean(levelMean,"all"))
        end
    end

    iscorrect = input('For next brightness level, change brightness then type 0. To end calibration image collection, type 1');

end %end while

master.sCMOS.ncals = ii-1;

end

