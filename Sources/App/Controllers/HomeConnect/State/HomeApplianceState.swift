struct HomeApplianceState {
    var appliance: HomeAppliance
    
    var status: [String: JSON]?
    var settings: [String: JSON]?
    
    var activeProgram: HomeAppliance.Program?
    var selectedProgram: HomeAppliance.Program?
}
