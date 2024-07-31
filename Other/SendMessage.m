function SendMessage(recipients,subject,message)
%Sends email to recipient email. Sets preferences to a dummy email created
%for this purpose.
%Used instead of sendmail as no preferences need to be set in other scripts

%SendMessage v1.0 4/20/22

mail = 'uiucmatlabmessage@gmail.com';  %Dummy email address
pwd  = 'NV-SMMChem'; %Dummy email password

%Sets preferences for sending emails using matlab
setpref('Internet','E_mail',mail);
setpref('Internet','SMTP_Server','smtp.gmail.com');
setpref('Internet','SMTP_Username',mail);
setpref('Internet','SMTP_Password',pwd);

%Does magic to make gmail work as dummy email
props = java.lang.System.getProperties;
props.setProperty('mail.smtp.auth','true');
props.setProperty('mail.smtp.starttls.enable',     'true');
props.setProperty('mail.smtp.socketFactory.class', 'javax.net.ssl.SSLSocketFactory');
props.setProperty('mail.smtp.socketFactory.port','465');

%Sends the email
sendmail(recipients,subject,message);

end

