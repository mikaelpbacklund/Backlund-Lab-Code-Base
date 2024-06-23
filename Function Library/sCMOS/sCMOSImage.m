function [averageImage,imageVariance] = sCMOSImage()
%Takes image using Hamamatsu camera. primary output is average image,
%secondary output is image variance.

%Instrument dependencies:
%Hamamatsu sCMOS camera

%Code dependencies:
%sCMOSInitialization

%Inputs:
%master.sCMOS.framesper : number of frames to take per image
%master.sCMOS.defect : in-built correction
%master.sCMOS.hotPixel : what level of correction should be used.
%Only relevant if master.sCMOS.defect == "on"

global hamm  %#ok<*GVMIS>
global master

if ~isfield(master,'notifications')
    master.notifications = true;
end

%Checks if sCMOS camera is initialized
iscorrect = false;
if isfield(master,'sCMOS')
   if isfield(master.sCMOS,'initialized')
      if islogical(master.sCMOS.initialized)
         iscorrect = master.sCMOS.intialized;
      end
   end
end
if ~iscorrect
    if master.notifications
        fprintf('sCMOS not initialized. Beginning intialization\n');
    end
    sCMOSInitialization()
end

try
   
   sCMOS = master.sCMOS;

    %Provides warning as well as some time to turn off lights if desired
    if isfield(sCMOS,'warningtime')
        if sCMOS.warningtime ~= 0
            if master.notifications
               fprintf('Beginning image collection. Please turn off lights in the next %d seconds\n',master.sCMOS.warningtime)
            end
            pause(sCMOS.warningtime)
        end
    end

    %Specifies image height and width
    sCMOS.iw = 1 + sCMOS.xbounds(2) - sCMOS.xbounds(1);
    sCMOS.ih = 1 + sCMOS.ybounds(2) - sCMOS.ybounds(1);

    %Preallocation
    im = zeros(2304,2304);
    imsq = im;

    %Frames taken in sets of 100 to not overload memory
    hamm.FramesPerTrigger = 100;
    nsets = ceil(sCMOS.framesper /100);
    lastset = mod(sCMOS.framesper,100);
    if lastset == 0
        lastset = 100;%if no remainder, set last set number of frames to 100
    end

    nframes = 100;
    for jj = 1:nsets

        %For the final set, change frames to left over value
        if jj == nsets
            hamm.FramesPerTrigger = lastset;
        end

        start(hamm)
        
        if jj == nsets
           nframes = lastset;
        end
        
        %Continues acquiring until all frames are available
        while get(hamm,'FramesAvailable') < nframes
           pause(.01)
        end
        
        if master.notifications
           fprintf('%d / %d frames complete\n',(jj-1)*100+nframes,sCMOS.framesper)
        end

        imageOut = getdata(hamm);%Obtains data from camera
        stop(hamm)
        %Converts to 3D array. unsure why a 4th is created in the first place
        imageOut = double(squeeze(imageOut));

        %Adds this set's sum to total sum
        im = im + sum(imageOut,3);
        imsq = imsq + sum(imageOut.^2,3);

    end

    %Divides by total number of frames to get average. also crops image
    im = im(sCMOS.ybounds(1):sCMOS.ybounds(2),sCMOS.xbounds(1):sCMOS.xbounds(2)) ./ sCMOS.framesper;
    imsq = imsq(sCMOS.ybounds(1):sCMOS.ybounds(2),sCMOS.xbounds(1):sCMOS.xbounds(2)) ./ sCMOS.framesper;

    imageVariance = imsq - im.^2;%Variance calculation

    sCMOS.imnum = sCMOS.imnum + 1;%Increments image number

    averageImage = im;%Sets output to image
    totalmax = max(im,[],"all");%Finds maximum for reporting

    %Sends email if desired
    if sCMOS.sendping 
       if isempty(sCMOS.emailaddress) && master.notifications
          fprintf('Email notifications on but no email address was provided\n')
       else
          msgsubject = sprintf('Image #%d Collection Complete',master.sCMOS.imnum);
          msgtext = sprintf('Max pixel value %.2f',totalmax);
          send_msg({sCMOS.emailaddress},msgsubject,msgtext);
       end
    end

    %Saves image if desired
    if sCMOS.saveimage
        savename = sprintf('Image #%d',sCMOS.imnum);
        save(savename,'averageImage','imageVariance')
    end
    
    if master.notifications
      fprintf('Image collection complete. Max pixel value %.2f\n',totalmax)
    end

    %Creates plots of mean image and variance map if desired
    if sCMOS.plots.mean
        currtitle = sprintf('Average Image #%d',sCMOS.imnum);
        figure ('Name',currtitle,'NumberTitle',"off")
        imagesc(im)
        colormap(gray(256));
        cb = colorbar;
        ylabel(cb,'Counts','FontSize',13,'Rotation',270,"FontWeight","normal");
        cb.Label.Position(1) = 3.3;
        title(currtitle)
        if sCMOS.plots.save
            saveas(gcf,append(currtitle,'.tif'))
        end
    end

    if sCMOS.plots.variance
        currtitle = sprintf('Variance of Image #%d',sCMOS.imnum);
        figure ('Name',currtitle,'NumberTitle',"off")
        imagesc(imageVariance)
        colormap(gray(256));
        cb = colorbar;
        ylabel(cb,'Counts','FontSize',13,'Rotation',270,"FontWeight","normal");
        cb.Label.Position(1) = 3.3;
        title(currtitle)
        if sCMOS.plots.save
            saveas(gcf,append(currtitle,'.tif'))
        end
    end
    
    master.sCMOS = sCMOS;

catch ME %If there is an error, send a ping if desired then rethrow error
    if sCMOS.sendping
        msgsubject = sprintf('Error in Image Collection');
        msgtext = sprintf(ME.message);
        send_msg({'dd4falcons@gmail.com'},msgsubject,msgtext);
    end
    master.sCMOS = sCMOS;
    rethrow(ME)
end

end

