function [] = sCMOSSplitCalibration_editing() %#ok<*FNDEF> 
%Creates calibration information using calibration image set

%Instrument dependencies:
%Hamamatsu sCMOS camera

%Code dependencies:
%sCMOSInitialization
%sCMOSCalImage

global master %#ok<*GVMIS> 

if ~isfield(master,'notifications')
    master.notifications =true;
end


if master.sCMOS.hotPixel == "all"
    hotrepeat = 3;
else
    hotrepeat = 1;
end

for mm = 1:hotrepeat
    
    if (master.sCMOS.hotPixel == "all" && mm == 1) || master.sCMOS.hotPixel == "minimum"
        hottitle = ' (Minimum)';
    elseif (master.sCMOS.hotPixel == "all" && mm == 2) || master.sCMOS.hotPixel == "standard"
        hottitle = ' (Standard)';
    elseif (master.sCMOS.hotPixel == "all" && mm == 3) || master.sCMOS.hotPixel == "aggressive"
        hottitle = ' (Aggressive)';
    end
    
    
    master.sCMOS.readnoise(:,:,mm) = master.sCMOS.darksqmean(:,:,mm) - master.sCMOS.darkmean(:,:,mm);

    if master.sCMOS.plots.dark 
        darktitle = append('Dark Offset',hottitle);
        figure ('Name',darktitle,'NumberTitle',"off")
        set(gcf,'Visible','on')
        imagesc(master.sCMOS.darkmean(:,:,mm))
        colormap(gray(256));
        aa=colorbar;
        ylabel(aa,'Counts','FontSize',13,'Rotation',270,"FontWeight","normal");
        aa.Label.Position(1) = 3.3;
        title(darktitle)
        if master.sCMOS.plots.save 
            saveas(gcf,append(darktitle,'.tif'))
        end

        readtitle = append('Read Noise',hottitle);
        figure ('Name',readtitle,'NumberTitle',"off")
        set(gcf,'Visible','on')
        imagesc(master.sCMOS.readnoise(:,:,mm))
        colormap(gray(256));
        aa=colorbar;
        ylabel(aa,'Counts','FontSize',13,'Rotation',270,"FontWeight","normal");
        aa.Label.Position(1) = 3.3;
        title('Read Noise',"FontWeight","normal","FontSize",12)
        if master.sCMOS.plots.save == 1
            saveas(gcf,append(readtitle,'.tif'))
        end

    end %end dark plots

    if master.sCMOS.groupsets == 0
        master.sCMOS.groupsets = 1:length(master.sCMOS.calmeans(1,1,:,mm));
    end

    ngroups = length(master.sCMOS.groupsets(:,1));
    master.sCMOS.gain(:,:,:,mm) = zeros(master.sCMOS.ih,master.sCMOS.iw,ngroups);
    master.sCMOS.norm(:,:,:,mm) = zeros(master.sCMOS.ih,master.sCMOS.iw,ngroups);

    for ii = 1:ngroups

        levels = master.sCMOS.groupsets(ii,:);
        levels(~levels) = [];%deletes extra 0s

        meanstack = squeeze(master.sCMOS.calmeans(:,:,levels,mm));
        varstack = master.sCMOS.calsqmeans(:,:,levels,mm)-master.sCMOS.calmeans(:,:,levels,mm);

        xaxis = squeeze(mean(mean(meanstack,2),1));

        for jj = 1:master.sCMOS.ih %For each row

            if floor(jj/100) == jj/100
                if master.notifications
                fprintf('Mapping %d / %d \n',jj,master.sCMOS.ih)
                end
            end

            for kk = 1:master.sCMOS.iw %For each column

                currmeans = squeeze(meanstack(jj,kk,:)) - master.sCMOS.darkmean(jj,kk,mm);
                currvars = squeeze(varstack(jj,kk,:)) - master.sCMOS.readnoise(jj,kk,mm);
                slopefit = currmeans\currvars;
                master.sCMOS.gain(jj,kk,ii,mm) = 1/slopefit;

                pfit = polyfit(xaxis,meanstack(jj,kk,:),1);%do with \ ?
                master.sCMOS.norm(jj,kk,ii,mm) = pfit(1);

            end

        end

        if master.sCMOS.plots.gain == 1
            currname = append(append(append('Group ',num2str(ii)),' Gain'),hottitle);
            figure ('Name',currname,'NumberTitle',"off")
            set(gcf,'Visible','on')
            imagesc(master.sCMOS.gain(:,:,ii,mm))
            colormap(gray(256));
            aa=colorbar;
            ylabel(aa,'Electrons per Count','FontSize',13,'Rotation',270,"FontWeight","normal");
            aa.Label.Position(1) = 3.3;
            title(currname,"FontWeight","normal","FontSize",12)
            if master.sCMOS.plots.save == 1
                saveas(gcf,append(currname,'.tif'))
            end
        end

        if master.sCMOS.plots.norm == 1
            currname = append(append(append('Group ',num2str(ii)),' Normalization'),hottitle);
            figure ('Name',currname,'NumberTitle',"off")
            set(gcf,'Visible','on')
            imagesc(master.sCMOS.norm(:,:,ii,mm))
            colormap(gray(256));
            colorbar
            title(append(currname,' Map of Pixel Brightness as a Ratio to Mean Brightness'),"FontWeight","normal","FontSize",12)
            if master.sCMOS.plots.save == 1
                saveas(gcf,append(currname,'.tif'))
            end
        end

        if master.sCMOS.plots.pixels.n ~= 0

            pixLoc = zeros(pixn,2);
            lgdvec = string(zeros(pixn,1));

            mean_x_axis=squeeze(mean(mean(meanstack,1),2));

            meanname = append(append('Group ',append(num2str(ii),' Pixel Relative Response')),hottitle);
            figure ('Name',meanname,'NumberTitle',"off");
            meanFig = get(gcf,'Number');

            gainname = append(append('Group ',append(num2str(ii),' Pixel Gains')),hotttitle);
            figure ('Name',gainname,'NumberTitle',"off");
            gainFig = get(gcf,'Number');

            for jj = 1:master.sCMOS.plots.pixels.n
                currrow = master.sCMOS.plots.pixels.rows(jj);
                currcolumn = master.sCMOS.plots.pixels.columns(jj);

                if currrow ~= 0

                    if currcolumn ~=0

                        pixLoc(jj,:) = [currrow currcolumn];

                    else

                        pixLoc(jj,:) = [pixrs(jj) randi([1 master.sCMOS.iw])];

                    end

                elseif pixcs(jj) ~=0

                    pixLoc(jj,:) = [randi([1 master.sCMOS.ih]) pixcs(jj)];

                else

                    pixLoc(jj,:) = [randi([1 master.sCMOS.ih]) randi([1 master.sCMOS.iw])];

                end %End pixel location if

                pixmean = squeeze(meanstack(pixLoc(jj,1),pixLoc(jj,2),:));

                pixvar = squeeze(varstack(pixLoc(jj,1),pixLoc(jj,2),:));
                pixgain = 1./(pixvar./pixmean);

                set(0, 'CurrentFigure', meanFig)
                hold on
                plot(mean_x_axis,pixmean ./ mean_x_axis)

                set(0, 'CurrentFigure', gainFig)
                hold on
                plot(pixmean,pixgain)

                lgdvec(jj) = sprintf("Pixel R%d C%d",pixLoc(jj,1),pixLoc(jj,2));

            end %End different pixels loop

            master.sCMOS.plots.pixels.locations(:,:,ii,mm) = pixLoc;
            master.sCMOS.plots.pixels.means(:,:,ii,mm) = pixmean;
            master.sCMOS.plots.pixels.vars(:,:,ii,mm) = pixvar;
            master.sCMOS.plots.pixels.gain(:,:,ii,mm) = pixgain;

            for jj=1:2

                if jj == 1
                    set(0, 'CurrentFigure', meanFig)
                    ylabel('Pixel Response Relative to Mean')
                    xlabel('Image Mean Intensity (Counts)')
                    title(meanname)
                    if master.sCMOS.plots.save == 1
                        saveas(gcf,append(meanname,'.tif'))
                    end
                else
                    set(0, 'CurrentFigure', gainFig)
                    xlabel('Pixel Intensity (Counts)')
                    ylabel('Pixel(s) Gain (e^{-}/Counts)')
                    title(gainname)
                    if master.sCMOS.plots.save == 1
                        saveas(gcf,append(gainname,'.tif'))
                    end
                end

                lgd=legend(lgdvec);
                lgd.Location = 'northeastoutside';
                hold off

            end %end mean/gain plotting

        end %end pixels

    end%end groups

end

end

