// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'SplitBalance';

  @override
  String get bills => 'Bills';

  @override
  String get splitsAndCategories => 'Splits & Categories';

  @override
  String get summary => 'Summary';

  @override
  String get settings => 'Settings';

  @override
  String get addBill => 'Add Bill';

  @override
  String get editBill => 'Edit Bill';

  @override
  String get deleteBill => 'Delete Bill';

  @override
  String get areYouSureDeleteBill =>
      'Are you sure you want to delete this bill?';

  @override
  String get cancel => 'Cancel';

  @override
  String get delete => 'Delete';

  @override
  String get edit => 'Edit';

  @override
  String get save => 'Save';

  @override
  String get add => 'Add';

  @override
  String get retry => 'Retry';

  @override
  String get refresh => 'Refresh';

  @override
  String get addBillTooltip => 'Add Bill';

  @override
  String get refreshTooltip => 'Refresh';

  @override
  String error(String error) {
    return 'Error: $error';
  }

  @override
  String get noBillsYet => 'No bills yet';

  @override
  String get addYourFirstBill => 'Add Your First Bill';

  @override
  String get bill => 'Bill';

  @override
  String get date => 'Date';

  @override
  String get amount => 'Amount';

  @override
  String get paidBy => 'Paid by';

  @override
  String get category => 'Category';

  @override
  String get selectWhoPaid => 'Please select who paid';

  @override
  String get selectCategory => 'Please select a category';

  @override
  String get enterValidAmount => 'Please enter a valid amount';

  @override
  String get details => 'Details';

  @override
  String get selectStorageFolder => 'Select Storage Folder';

  @override
  String get folderSelected => 'Folder selected! Checking folder data...';

  @override
  String get signOut => 'Sign Out?';

  @override
  String get signOutConfirmation =>
      'Do you want to sign out? You can sign back in later.';

  @override
  String get signOutButton => 'Sign Out';

  @override
  String get refreshFolders => 'Refresh Folders';

  @override
  String get enterPersonNames => 'Enter Person Names';

  @override
  String get enterPersonNamesPrompt =>
      'Please enter the names of the two people for this folder:';

  @override
  String get folderContainsDifferentNames =>
      'The folder contains data with different person names. Please enter the correct names:';

  @override
  String get person1Name => 'Person 1 Name';

  @override
  String get person2Name => 'Person 2 Name';

  @override
  String get enterFirstName => 'Enter first person\'s name';

  @override
  String get enterSecondName => 'Enter second person\'s name';

  @override
  String get enterBothPersonNames => 'Please enter both person names';

  @override
  String get changeFolder => 'Change Folder';

  @override
  String get createCategories => 'Create Categories';

  @override
  String get createCategoriesPrompt =>
      'You need to create at least one category before you can add bills.\n\nPlease go to the \"Splits & Categories\" tab in the bottom navigation to create categories.';

  @override
  String get changePersonNames => 'Change Person Names';

  @override
  String get goToCategories => 'Go to Categories';

  @override
  String get pleaseSignInFirst => 'Please sign in first';

  @override
  String errorLoadingFolders(String error) {
    return 'Error loading folders: $error';
  }

  @override
  String get createNewFolder => 'Create New Folder';

  @override
  String folderCreatedSuccessfully(String folderName) {
    return 'Folder \"$folderName\" created successfully';
  }

  @override
  String errorCreatingFolder(String error) {
    return 'Error creating folder: $error';
  }

  @override
  String get configSaved => 'Configuration saved successfully';

  @override
  String errorSavingConfig(String error) {
    return 'Error saving config: $error';
  }

  @override
  String get configuration => 'Configuration';

  @override
  String get signInRequired => 'Sign in required';

  @override
  String get signInRequiredMessage =>
      'Please sign in with your Google account to access all features of SplitBalance.';

  @override
  String get signInWithGoogle => 'Sign In with Google';

  @override
  String get folderSelectionRequired => 'Folder Selection Required';

  @override
  String get folderSelectionRequiredMessage =>
      'Please select a Google Drive folder to store your data.';

  @override
  String get personNamesRequired => 'Person Names Required';

  @override
  String get personNamesRequiredMessage =>
      'Please enter the names of both people using this folder.';

  @override
  String get navigateToFolder => 'Navigate to Folder';

  @override
  String get loading => 'Loading...';

  @override
  String get loadingPath => 'Loading path...';

  @override
  String get create => 'Create';

  @override
  String get myDrive => 'My Drive';

  @override
  String get unnamed => 'Unnamed';

  @override
  String folderSelectedAndSaved(String folderName) {
    return 'Folder \"$folderName\" selected and saved. Checking folder data...';
  }

  @override
  String get selectFolderFirst => 'Select a folder first';

  @override
  String get folderMustBeSelected => 'Folder must be selected';

  @override
  String get theme => 'Theme';

  @override
  String get light => 'Light';

  @override
  String get dark => 'Dark';

  @override
  String get pink => 'Pink';

  @override
  String get language => 'Language';

  @override
  String get english => 'English';

  @override
  String get french => 'French';

  @override
  String get clearAllConfiguration => 'Clear All Configuration?';

  @override
  String get clearAllConfigMessage =>
      'This will:\n\n• Sign out from Google\n• Clear folder selection\n• Clear person names\n• Clear all saved settings\n\nThis action cannot be undone.';

  @override
  String get clearAllConfigurationButton => 'Clear All Configuration';

  @override
  String get clearAll => 'Clear All';

  @override
  String get allConfigCleared => 'All configuration cleared';

  @override
  String get calculateBalances => 'Calculate Balances';

  @override
  String get addPaymentSplit => 'Add Payment Split';

  @override
  String get editPaymentSplit => 'Edit Payment Split';

  @override
  String get startDate => 'Start Date';

  @override
  String get endDate => 'End Date';

  @override
  String get allCategories => 'All Categories';

  @override
  String personPercentage(String personName) {
    return '$personName Percentage';
  }

  @override
  String personPercentageDisplay(String personName, String percentage) {
    return '$personName Percentage: $percentage%';
  }

  @override
  String paymentSplitPersonDisplay(String personName, String percentage) {
    return '$personName: $percentage%';
  }

  @override
  String get deletePaymentSplit => 'Delete Payment Split';

  @override
  String get deletePaymentSplitMessage =>
      'Are you sure you want to delete this payment split?';

  @override
  String get noPaymentSplits => 'No payment splits yet';

  @override
  String get noCategories => 'No categories yet';

  @override
  String get addCategory => 'Add Category';

  @override
  String get editCategory => 'Edit Category';

  @override
  String get deleteCategory => 'Delete Category';

  @override
  String deleteCategoryMessage(String categoryName) {
    return 'Are you sure you want to delete \"$categoryName\"?';
  }

  @override
  String get categoryInUse => 'Cannot delete category that is in use';

  @override
  String get categoryInUseSubtitle =>
      'This category is being used by bills or payment splits. Please remove or change them first.';

  @override
  String get enterCategoryName => 'Please enter a category name';

  @override
  String get dismiss => 'Dismiss';

  @override
  String get paymentSplits => 'Payment Splits';

  @override
  String get categories => 'Categories';

  @override
  String get recalculate => 'Recalculate';

  @override
  String get noBalanceCalculated => 'No balance calculated';

  @override
  String get allBalanced => 'All Balanced!';

  @override
  String get netBalance => 'Net Balance';

  @override
  String get paid => 'Paid';

  @override
  String get expected => 'Expected';

  @override
  String get difference => 'Difference';

  @override
  String get categoryBreakdown => 'Category Breakdown';

  @override
  String get statistics => 'Statistics';

  @override
  String get totalBills => 'Total Bills';

  @override
  String get totalAmount => 'Total Amount';

  @override
  String get saveBill => 'Save Bill';

  @override
  String get enterAmount => 'Please enter an amount';

  @override
  String get detailsOptional => 'Details (optional)';

  @override
  String get noCategoriesAvailable =>
      'No categories available. Please add categories in the Payment Splits & Categories screen.';

  @override
  String errorSavingBill(String error) {
    return 'Error saving bill: $error';
  }

  @override
  String get to => 'to';

  @override
  String get addCategoriesToOrganize => 'Add categories to organize your bills';

  @override
  String get inUseCannotDelete => 'In use (cannot delete)';

  @override
  String get googleDriveConnection => 'Google Drive Connection';

  @override
  String get googleDriveFolder => 'Google Drive Folder';

  @override
  String get selectGoogleDriveFolderPrompt =>
      'Please select a Google Drive folder where your data will be stored:';

  @override
  String get selectGoogleDriveFolderMessage =>
      'Please select a Google Drive folder where your data will be stored. You must select a folder before accessing other features.';

  @override
  String get personNames => 'Person Names';

  @override
  String get selectOrNavigateFolder => 'Select or navigate into a folder:';

  @override
  String get saveConfiguration => 'Save Configuration';

  @override
  String get goBack => 'Go back';

  @override
  String get navigateIntoFolder => 'Navigate into folder';

  @override
  String get selectThisFolder => 'Select this folder';

  @override
  String get allBalancedNoOneOwes => 'All balanced! No one owes anyone.';

  @override
  String personOwesPerson(String person1, String person2, String amount) {
    return '$person1 owes $person2 $amount';
  }

  @override
  String get currentlyUsedFolder => 'Currently Used Folder:';

  @override
  String get folderName => 'Folder Name';

  @override
  String get enterFolderName => 'Enter folder name';
}
