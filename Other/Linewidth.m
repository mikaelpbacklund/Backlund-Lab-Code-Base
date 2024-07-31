function outnum = Linewidth(Diffusion, analysistype, innum)

if strcmp(analysistype,'linewidth')
    outnum = 6*Diffusion/pi/innum^2;
elseif strcmp(analysistype, 'LW')
    outnum = 6*Diffusion/pi/innum^2;
elseif strcmp(analysistype, 'depth')
    outnum =  sqrt(6*Diffusion/pi/innum);
else
    error('Second input must be either LW or depth')

end
end