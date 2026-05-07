import { LightningElement, api, track, wire } from 'lwc';
import getActiveUsers from '@salesforce/apex/RoundRobinConfiguratorController.getActiveUsers'; // You need to add this method

const COLUMNS = [
    { label: 'Name', fieldName: 'Name' },
    { label: 'Email', fieldName: 'Email', type: 'email' },
    { label: 'Profile', fieldName: 'ProfileName' }, 
    // Add custom columns here later for "Daily Cap" using custom types if needed
];

export default class RrTeamManager extends LightningElement {
    @api role;
    @api selectedUsers = []; // Array of IDs passed from Parent

    @track allUsers = [];
    @track filteredUsers = [];
    @track columns = COLUMNS;
    @track selectedUserIds = [];

    connectedCallback() {
        // Initialize selection from parent data
        if(this.selectedUsers) {
            this.selectedUserIds = [...this.selectedUsers];
        }
    }

    @wire(getActiveUsers)
    wiredUsers({ error, data }) {
        if (data) {
            // Flatten data if needed (e.g. Profile.Name -> ProfileName)
            this.allUsers = data.map(u => ({
                Id: u.Id,
                Name: u.Name,
                Email: u.Email,
                ProfileName: u.Profile?.Name
            }));
            this.filteredUsers = this.allUsers;
        } else if (error) {
            console.error(error);
        }
    }

    handleSearch(event) {
        const key = event.target.value.toLowerCase();
        if(!key) {
            this.filteredUsers = this.allUsers;
        } else {
            this.filteredUsers = this.allUsers.filter(u => 
                u.Name.toLowerCase().includes(key) || 
                (u.ProfileName && u.ProfileName.toLowerCase().includes(key))
            );
        }
    }

    handleRowSelection(event) {
        const selectedRows = event.detail.selectedRows;
        const selectedIds = selectedRows.map(row => row.Id);
        
        // Notify Parent (rrWizard) immediately
        const updateEvent = new CustomEvent('update', {
            detail: {
                role: this.role,
                userIds: selectedIds
            }
        });
        this.dispatchEvent(updateEvent);
        
        this.selectedCount = selectedIds.length;
    }

    get selectedCount() {
        return this.selectedUserIds.length;
    }
}