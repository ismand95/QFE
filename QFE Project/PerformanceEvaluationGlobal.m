clear %Removes all variables from the workspace
clc %Clears the command window
close all %Deletes all figures


%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Controller-variables %%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%

makePlot = true;
globalDK = 'DK'; % Set to `GL´ for global and `DK´ for Denmark
m = 1000; %Number of bootstraps

tlower = datetime(2010,01,01); % start date
tupper = datetime(2020,08,01); % end date

%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Controller-variables %%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%


if strcmp(globalDK, 'DK')
    % read data from returns sheet
    Data = readtable('Samlet Data - Danske Fonde.xlsx', 'Sheet', 'returns', 'PreserveVariableNames', true);

    % read rowNames for output columns
    meta = readtable('Samlet Data - Danske Fonde.xlsx', 'Sheet', 'meta', 'PreserveVariableNames', true); 

elseif strcmp(globalDK, 'GL')
    % read data from returns sheet
    Data = readtable('Samlet Data - Globale Fonde.xlsx', 'Sheet', 'returns', 'PreserveVariableNames', true);

    % read rowNames for output columns
    meta = readtable('Samlet Data - Globale Fonde.xlsx', 'Sheet', 'meta', 'PreserveVariableNames', true); 
end


rowNames = table2array(meta(:,1));
aktivPassiv = table2array(meta(:,5));

% boolean indexing for dates between lower and upper interval
tf_Data = isbetween(Data.DATE, tlower, tupper);

% drop dates out of range
Data = Data(tf_Data,:);

% drop DATE column and convert to MATLAB matrix - for both Factors and MFs
Data.DATE = [];
Data = table2array(Data);

CIBOR_M1_deAnal = Data(:,1);

% define return and factors - annualized
rm = 12*100*Data(:,2);
smb = 12*100*Data(:,3);
hml = 12*100*Data(:,4);

% Mutual funds - create excess returns
mf = Data(:,5:end) - CIBOR_M1_deAnal;
mf = 12*100*mf;

% sizes of dataset
n  = size(mf,2); %The number of mutual funds in our data
T  = size(mf,1); %The number of time series observations

results = zeros(n,12); %Initiate a matrix to store regression results
alpha = zeros(n,1); %Initiate a vector to contain the estimated alphas
alpha_b = zeros(n,m); %Initiate a matrix to contain the bootstrapped alphas
rng(5);%Seed the random number generator


for i=1:n %Do the following for each fund i
    i %Show progress in the command window
    linMdl = fitlm([rm smb hml],mf(:,i)); %Estimate R_i=a+b*R_m+s*SMB+h*HML+e
    results(i,1) = linMdl.Coefficients{1,1}; %Store the a
    results(i,2) = linMdl.Coefficients{1,3}; %Store the t-statistic for a=0
    results(i,3) = linMdl.Coefficients{2,1}; %Store b
    results(i,4) = (linMdl.Coefficients{2,1}-1)/linMdl.Coefficients{2,2}; %Store the t-statistic for b=1
    results(i,5) = linMdl.Coefficients{3,1}; %Store the s
    results(i,6) = linMdl.Coefficients{3,3}; %Store the t-statistic for s=0
    results(i,7) = linMdl.Coefficients{4,1}; %Store the h
    results(i,8) = linMdl.Coefficients{4,3}; %Store the t-statistic for h=0
    results(i,9) = linMdl.Rsquared.Ordinary; %Store the R^2
    res = linMdl.Residuals{:,1}; %Extract residuals
    alpha(i) = linMdl.Coefficients{1,1}; %Store the estimated alpha for fund i
    
    
    for j=1:m %Run the bootstrap for fund i
        res_b = datasample(res,T); %Randomly draw T residuals with replacement
        mf_b = linMdl.Coefficients{2,1}*rm+linMdl.Coefficients{3,1}*smb+linMdl.Coefficients{4,1}*hml+res_b; %Generate excess returns under H0: a=0
        linMdl_b = fitlm([rm smb hml],mf_b); %Estimate R_i=a+b*R_m+s*SMB+h*HML+e on bootstrapped mutual fund returns
        alpha_b(i,j) = linMdl_b.Coefficients{1,1}; %Store the bootstrapped alphas
    end
end

[alpha_s,index] = sort(alpha); %Sort the alphas to find the appropriate ranking of the individual funds
alpha_b_s = sort(alpha_b); %Sort the bootstrapped alphas

cv_05 = quantile(alpha_b_s,0.05,2); %Compute the 5% critical value across the sorted distributions
cv_95 = quantile(alpha_b_s,0.95,2); %Compute the 95% critical value across the sorted distributions


for i=1:n %Run a loop to store the critical values for the individual funds
    results(i,10) = cv_05(index==i); %Store the 5% critical value
    results(i,11) = cv_95(index==i); %Store the 95% critical value
    if alpha(i)<cv_05(index==i) %If the estimated alpha is below the lower critical value...
        results(i,12) = 1; %...report a 1 
    elseif alpha(i)>cv_95(index==i) %Else if the estimated alpha is above the upper critical value...
        results(i,12) = 2; %...report a 2 and a 0 otherwise      
    end
end

% Compiling results
results = round(results,2); %Round the results to two decimals
varNames = {'Aktiv/Passiv','Alpha','ta','b','tb','s','ts','h','th','R2','CV5', 'CV95','sig'}; %Define headers in the following table
res_table = table(aktivPassiv,results(:,1),results(:,2),results(:,3),results(:,4),results(:,5),results(:,6),results(:,7),results(:,8),results(:,9),results(:,10),results(:,11),results(:,12),'VariableNames',varNames,'RowNames',rowNames); %Collect and display the test results in a table 

res_table = sortrows(res_table, 'ta');

res_table

% Plotting
[ft,xt] = ksdensity(alpha_b_s(end,:)); %Construct a smoothed density function for the best performing fund.
[fb,xb] = ksdensity(alpha_b_s(1,:)); %Construct a smoothed density function for the worst performing fund.
[fa,xa] = ksdensity(alpha_s); %Construct a smoothed density function for the alphas.
[fab,xab] = ksdensity(mean(alpha_b_s,2)); %Construct a smoothed density function for the bootstrapped alphas.


if makePlot
    figure %Initiate a figure
    subplot(3,1,1) %Consider the first subplot in dimension 3x1  
    plot(xt,ft) %Plot the bootstrapped distribution for the best performing fund
    line([alpha_s(end), alpha_s(end)], ylim, 'LineWidth', 2, 'Color', 'r'); %Add a line for estimated alpha for the best performing fund
    title('Distribution for best performing fund'); %Add a title
    subplot(3,1,2) %Consider the second subplot and do the same for the worst performing fund
    plot(xb,fb)
    line([alpha_s(1), alpha_s(1)], ylim, 'LineWidth', 2, 'Color', 'r');
    title('Distribution for worst performing fund');
    subplot(3,1,3) %Consider the third subplot
    plot(xa,fa) %Plot the cross-sectional distribution of the estimated alphas
    hold on; %This command ensures that we do not overwrite the above plot when adding a new plot to the figure
    plot(xab,fab) %Plot the cross-sectional distribution of the bootstrapped alphas
    legend('Estimated alphas','Bootstrapped alphas') %Add legends
    title('Cross-sectional alpha distribution') %Add title
end
