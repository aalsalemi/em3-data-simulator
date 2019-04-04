clear
clc
close all
tic

total = readtable('C:\Users\User\Dropbox\em3\Datasets\France\New CSV-Files\household_power_consumption.txt');
app1 = readtable('C:\Users\User\Dropbox\em3\Datasets\France\New CSV-Files\Kitchen\microwave-bihour.csv');
app2 = readtable('C:\Users\User\Dropbox\em3\Datasets\France\New CSV-Files\Kitchen\dishwasher-bihour.csv');
app3 = readtable('C:\Users\User\Dropbox\em3\Datasets\France\New CSV-Files\Kitchen\oven-bihour.csv');
%%
num_apps = 3;

% Consumption power ratio is  (microwave-app1 1200: dishwasher-app2 1800:oven-app3 2400)
active_ratio = [1200,1800,2400];
% Standby rules: Microwave 7 Watts - dishwasher N/A  - Oven: 2 Watts
% Standby ration: 7:0:2
standbay_ratio = [7,0,2];
% Apps specs
% [max operating time in minutes , max active consumption in watts, max standby in watts]
app1_specs = [60   , 1200,7];
app2_specs = [60+45, 1800,2];
app3_specs = [3*60 , 2400,2];

total_power = 60*(str2double(total{:,7}));
day_time_slots = total{:,2};

app1_name = strings(length(day_time_slots),1);
app1_name(:,1)="microwave";

app2_name = strings(length(day_time_slots),1);
app2_name(:,1)="dishwasher";

app3_name = strings(length(day_time_slots),1);
app3_name(:,1)="oven";

%% Appliances On/Off micromoments
[app1_moments,app1_ons] = find_on_off_moments(app1,day_time_slots);
[app2_moments,app2_ons] = find_on_off_moments(app2,day_time_slots);
[app3_moments,app3_ons] = find_on_off_moments(app3,day_time_slots);

%% Remove clear clustering errors
% If any app is on while the consumption is below standby level, change it
% to off
[app1_moments,app1_ons] = fix_cluster_errors(app1_moments,app1_ons,total_power,app1_specs);
[app2_moments,app2_ons] = fix_cluster_errors(app2_moments,app2_ons,total_power,app2_specs);
[app3_moments,app3_ons] = fix_cluster_errors(app3_moments,app3_ons,total_power,app3_specs);

%% Appliances Power consumption (in Watts)
apps_power = find_each_app_consumption(total_power,[app1_ons,app2_ons,app3_ons],standbay_ratio,active_ratio,num_apps);

%% Occupancy assignments
% Room is occupied uniformly at random with 70% chance of 1 in the time
% from 09:00:00 till 19:00:00 and with 70% chance of 1 otherwise.
% Room is occupied anytime an app is switched on or off

% 1) generate random 1/0 with 70% zeros and 30% ones
occupancy = rand(length(day_time_slots),1) > 0.7 ;

% 2) find the index of all times from 09:00:00 till 19:00:00 and populate
% the index with 1/0 with 30% zeros and 70% ones
occ_active_idx = find(total{:,2}>= duration(9,0,0) & total{:,2}<= duration(19,0,0));
occupancy(occ_active_idx) = rand(length(occ_active_idx),1)<= 0.7;


% 3) change the occupancy to 1 any time any app is turned on or off
occupancy(unique([app1{:,1}+1;app2{:,1}+1;app3{:,1}+1])) = 1;

%% Add consumption while outside moments
app1_moments = add_outside_momoments(app1_moments,occupancy,app1_specs,apps_power(:,1));
app2_moments = add_outside_momoments(app2_moments,occupancy,app2_specs,apps_power(:,2));
app3_moments = add_outside_momoments(app3_moments,occupancy,app3_specs,apps_power(:,3));


%% Add excessive consumption moments

app1_moments = add_excessive_momoments(app1_moments,app1_specs,apps_power(:,1));
app2_moments = add_excessive_momoments(app2_moments,app2_specs,apps_power(:,2));
app3_moments = add_excessive_momoments(app3_moments,app3_specs,apps_power(:,3));



%% Write data into a .csv file
% Headers: Occupancy, Appliance, Time, Date, Power consumption , Micro-Moments
T1 = table(occupancy,app1_name,total{:,2},total{:,1},apps_power(:,1),app1_moments,'VariableNames',{'Occupancy', 'Appliance', 'Time', 'Date', 'PowerConsumption' , 'MicroMoments'});
T2 = table(occupancy,app2_name,total{:,2},total{:,1},apps_power(:,2),app2_moments,'VariableNames',{'Occupancy', 'Appliance', 'Time', 'Date', 'PowerConsumption' , 'MicroMoments'});
T3 = table(occupancy,app3_name,total{:,2},total{:,1},apps_power(:,3),app3_moments,'VariableNames',{'Occupancy', 'Appliance', 'Time', 'Date', 'PowerConsumption' , 'MicroMoments'});
T = [T1;T2;T3];

writetable(T,'simulated_kitchen_data.csv')
writetable(T,'simulated_kitchen_data.txt')
toc
%%

function [app_on_off_moments, app_ON] = find_on_off_moments(app,day_time_slots)
app_on_off_moments = zeros(length(day_time_slots),1);
app_ON = nan(length(day_time_slots),1);
% find all time and dates indicies of each app on/off records
app_times = app{:,1}+1;

% fill the on/off actions with 1/2 micromoments
app_on_off_moments(app_times) = action2moment(app{:,11});
app_ons = find(app_on_off_moments ==1);
app_offs = find(app_on_off_moments ==2);

% Make sure the first action is ON
if app_ons(1) > app_offs(1)
    app_ons = app_ons(2:end);
end

if app_ons(end) > app_offs(end)
    app_offs(end+1) = length(day_time_slots);
end
on_indx =[];
for k = 1:length(app_ons)
    on_indx=[on_indx, app_ons(k):app_offs(k)-1];
end
app_ON(on_indx)=1;
end



%%
function moment = action2moment(action)
moment = nan(numel(action),1);
for i = 1:numel(action)
    if strcmp(action{i},'on')
        moment(i) = 1;
    else
        moment(i) = 2;
    end
    
end

end
%%
function [fixed_app_moments,fixed_app_ons] = fix_cluster_errors(app_moments,app_ons,total_power,app_specs)
fixed_app_ons = app_ons;
fixed_app_moments = app_moments;
% 1) fix apps_ons
idx = (~isnan(app_ons)) & (total_power>=app_specs(3));
fixed_app_ons(~idx)=nan;
% 2) fix apps_on_off moments
for i =1 :length(app_moments)-1
    if isnan(fixed_app_ons(i)) && fixed_app_ons(i+1)==1
        fixed_app_moments(i+1)=1;
    elseif fixed_app_ons(i)==1 && isnan(fixed_app_ons(i+1))
        fixed_app_moments(i+1)=2;
    end
end
end

%%
function apps_power = find_each_app_consumption(total_day_power,all_apps_on_off,standbay_ratio,active_ratio,num_apps)
apps_on_idx = ~isnan(all_apps_on_off);
apps_power = nan(length(total_day_power),num_apps);

parfor i = 1:length(apps_on_idx)
    if sum(apps_on_idx(i,:)) == 0
        % Split total power by the standby ratio
        apps_power(i,:) = total_day_power(i).*standbay_ratio./sum(standbay_ratio);
    else
        % Split the total power by the active_ratio x on_idx
        active_on_off_ratio = active_ratio .* apps_on_idx(i,:);
        apps_power(i,:) = total_day_power(i).*active_on_off_ratio./sum(active_on_off_ratio);
    end
end

end



%%
function app_moments = add_outside_momoments(app_moments,occupancy,app_excess,app_power)
turn_on = find(app_moments==1);
turn_off = find(app_moments==2);

if length(turn_off) < length(turn_on) % App remains on till the end of the recording
    final_indx = length(turn_off);
else
    final_indx = length(turn_on);
end

for i = 1:final_indx
    occ_flag = occupancy(turn_on(i)+1:turn_off(i)-1);
    app_moments(turn_on(i)+1:turn_off(i)-1)= 4*(~occ_flag);
    
end


end

%%
function app_moments = add_excessive_momoments(app_moments,app_excess,app_power)

turn_on = find(app_moments==1);
turn_off = find(app_moments==2);
if length(turn_off) < length(turn_on) % App remains on till the end of the recording
    turn_off = [turn_off;length(app_moments)+1];
end

for i = 1:length(turn_on)
    
    % Assign excessive moment (3) if:
    %1) Operation time exceeds 0.99 of max aoperation time and app consumes
    % more than standby power
    %2) Or: power consumption exceeds 0.99 max consumption
    
    min_count = 0;
    for k = turn_on(i)+1:turn_off(i)-1
        min_count = min_count+1;
        if min_count >= 0.99* app_excess(1) && app_power(k) >= 0.90*app_excess(2)
            app_moments(k)= 3;
            
        end
        
        
       
    end
    
end


end

