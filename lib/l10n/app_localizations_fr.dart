// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appTitle => 'SplitBalance';

  @override
  String get bills => 'Factures';

  @override
  String get splitsAndCategories => 'Répartitions et Catégories';

  @override
  String get summary => 'Résumé';

  @override
  String get settings => 'Paramètres';

  @override
  String get addBill => 'Ajouter une facture';

  @override
  String get editBill => 'Modifier la facture';

  @override
  String get deleteBill => 'Supprimer la facture';

  @override
  String get areYouSureDeleteBill =>
      'Êtes-vous sûr de vouloir supprimer cette facture ?';

  @override
  String get cancel => 'Annuler';

  @override
  String get delete => 'Supprimer';

  @override
  String get edit => 'Modifier';

  @override
  String get save => 'Enregistrer';

  @override
  String get add => 'Ajouter';

  @override
  String get retry => 'Réessayer';

  @override
  String get refresh => 'Actualiser';

  @override
  String get addBillTooltip => 'Ajouter une facture';

  @override
  String get refreshTooltip => 'Actualiser';

  @override
  String error(String error) {
    return 'Erreur : $error';
  }

  @override
  String get noBillsYet => 'Aucune facture pour le moment';

  @override
  String get addYourFirstBill => 'Ajouter votre première facture';

  @override
  String get bill => 'Facture';

  @override
  String get date => 'Date';

  @override
  String get amount => 'Montant';

  @override
  String get paidBy => 'Payé par';

  @override
  String get category => 'Catégorie';

  @override
  String get selectWhoPaid => 'Veuillez sélectionner qui a payé';

  @override
  String get selectCategory => 'Veuillez sélectionner une catégorie';

  @override
  String get enterValidAmount => 'Veuillez entrer un montant valide';

  @override
  String get details => 'Détails';

  @override
  String get selectStorageFolder => 'Sélectionner le dossier de stockage';

  @override
  String get folderSelected =>
      'Dossier sélectionné ! Vérification des données du dossier...';

  @override
  String get signOut => 'Se déconnecter ?';

  @override
  String get signOutConfirmation =>
      'Voulez-vous vous déconnecter ? Vous pourrez vous reconnecter plus tard.';

  @override
  String get signOutButton => 'Se déconnecter';

  @override
  String get refreshFolders => 'Actualiser les dossiers';

  @override
  String get enterPersonNames => 'Entrer les noms des personnes';

  @override
  String get enterPersonNamesPrompt =>
      'Veuillez entrer les noms des deux personnes pour ce dossier :';

  @override
  String get folderContainsDifferentNames =>
      'Le dossier contient des données avec des noms différents. Veuillez entrer les noms corrects :';

  @override
  String get person1Name => 'Nom de la personne 1';

  @override
  String get person2Name => 'Nom de la personne 2';

  @override
  String get enterFirstName => 'Entrer le nom de la première personne';

  @override
  String get enterSecondName => 'Entrer le nom de la deuxième personne';

  @override
  String get enterBothPersonNames =>
      'Veuillez entrer les deux noms de personnes';

  @override
  String get changeFolder => 'Changer de dossier';

  @override
  String get createCategories => 'Créer des catégories';

  @override
  String get createCategoriesPrompt =>
      'Vous devez créer au moins une catégorie avant de pouvoir ajouter des factures.\n\nVeuillez aller à l\'onglet \"Répartitions et Catégories\" dans la navigation en bas pour créer des catégories.';

  @override
  String get changePersonNames => 'Changer les noms des personnes';

  @override
  String get goToCategories => 'Aller aux catégories';

  @override
  String get pleaseSignInFirst => 'Veuillez d\'abord vous connecter';

  @override
  String errorLoadingFolders(String error) {
    return 'Erreur lors du chargement des dossiers : $error';
  }

  @override
  String get createNewFolder => 'Créer un nouveau dossier';

  @override
  String folderCreatedSuccessfully(String folderName) {
    return 'Dossier \"$folderName\" créé avec succès';
  }

  @override
  String errorCreatingFolder(String error) {
    return 'Erreur lors de la création du dossier : $error';
  }

  @override
  String get configSaved => 'Configuration enregistrée avec succès';

  @override
  String errorSavingConfig(String error) {
    return 'Erreur lors de l\'enregistrement de la configuration : $error';
  }

  @override
  String get configuration => 'Configuration';

  @override
  String get signInRequired => 'Connexion requise';

  @override
  String get signInRequiredMessage =>
      'Veuillez vous connecter avec votre compte Google pour accéder à toutes les fonctionnalités de SplitBalance.';

  @override
  String get signInWithGoogle => 'Se connecter avec Google';

  @override
  String get folderSelectionRequired => 'Sélection de dossier requise';

  @override
  String get folderSelectionRequiredMessage =>
      'Veuillez sélectionner un dossier Google Drive pour stocker vos données.';

  @override
  String get personNamesRequired => 'Noms des personnes requis';

  @override
  String get personNamesRequiredMessage =>
      'Veuillez entrer les noms des deux personnes utilisant ce dossier.';

  @override
  String get navigateToFolder => 'Naviguer vers le dossier';

  @override
  String get loading => 'Chargement...';

  @override
  String get loadingPath => 'Chargement du chemin...';

  @override
  String get create => 'Créer';

  @override
  String get myDrive => 'Mon Drive';

  @override
  String get unnamed => 'Sans nom';

  @override
  String folderSelectedAndSaved(String folderName) {
    return 'Dossier \"$folderName\" sélectionné et enregistré. Vérification des données du dossier...';
  }

  @override
  String get selectFolderFirst => 'Sélectionnez d\'abord un dossier';

  @override
  String get folderMustBeSelected => 'Un dossier doit être sélectionné';

  @override
  String get theme => 'Thème';

  @override
  String get light => 'Clair';

  @override
  String get dark => 'Sombre';

  @override
  String get pink => 'Rose';

  @override
  String get language => 'Langue';

  @override
  String get english => 'Anglais';

  @override
  String get french => 'Français';

  @override
  String get clearAllConfiguration => 'Effacer toute la configuration ?';

  @override
  String get clearAllConfigMessage =>
      'Cela va :\n\n• Vous déconnecter de Google\n• Effacer la sélection du dossier\n• Effacer les noms des personnes\n• Effacer tous les paramètres enregistrés\n\nCette action ne peut pas être annulée.';

  @override
  String get clearAllConfigurationButton => 'Effacer toute la configuration';

  @override
  String get clearAll => 'Tout effacer';

  @override
  String get allConfigCleared => 'Toute la configuration a été effacée';

  @override
  String get calculateBalances => 'Calculer les soldes';

  @override
  String get addPaymentSplit => 'Ajouter une répartition de paiement';

  @override
  String get editPaymentSplit => 'Modifier la répartition de paiement';

  @override
  String get startDate => 'Date de début';

  @override
  String get endDate => 'Date de fin';

  @override
  String get allCategories => 'Toutes les catégories';

  @override
  String personPercentage(String personName) {
    return '$personName Pourcentage';
  }

  @override
  String personPercentageDisplay(String personName, String percentage) {
    return '$personName Pourcentage : $percentage%';
  }

  @override
  String paymentSplitPersonDisplay(String personName, String percentage) {
    return '$personName : $percentage%';
  }

  @override
  String get deletePaymentSplit => 'Supprimer la répartition de paiement';

  @override
  String get deletePaymentSplitMessage =>
      'Êtes-vous sûr de vouloir supprimer cette répartition de paiement ?';

  @override
  String get noPaymentSplits => 'Aucune répartition de paiement pour le moment';

  @override
  String get noCategories => 'Aucune catégorie pour le moment';

  @override
  String get addCategory => 'Ajouter une catégorie';

  @override
  String get editCategory => 'Modifier la catégorie';

  @override
  String get deleteCategory => 'Supprimer la catégorie';

  @override
  String deleteCategoryMessage(String categoryName) {
    return 'Êtes-vous sûr de vouloir supprimer \"$categoryName\" ?';
  }

  @override
  String get categoryInUse =>
      'Impossible de supprimer une catégorie qui est utilisée';

  @override
  String get categoryInUseSubtitle =>
      'Cette catégorie est utilisée par des factures ou des répartitions de paiement. Veuillez d\'abord les supprimer ou les modifier.';

  @override
  String get enterCategoryName => 'Veuillez entrer un nom de catégorie';

  @override
  String get dismiss => 'Ignorer';

  @override
  String get paymentSplits => 'Répartitions de paiement';

  @override
  String get categories => 'Catégories';

  @override
  String get recalculate => 'Recalculer';

  @override
  String get noBalanceCalculated => 'Aucun solde calculé';

  @override
  String get allBalanced => 'Tout équilibré !';

  @override
  String get netBalance => 'Solde net';

  @override
  String get paid => 'Payé';

  @override
  String get expected => 'Attendu';

  @override
  String get difference => 'Différence';

  @override
  String get categoryBreakdown => 'Répartition par catégorie';

  @override
  String get statistics => 'Statistiques';

  @override
  String get totalBills => 'Total des factures';

  @override
  String get totalAmount => 'Montant total';

  @override
  String get saveBill => 'Enregistrer la facture';

  @override
  String get enterAmount => 'Veuillez entrer un montant';

  @override
  String get detailsOptional => 'Détails (optionnel)';

  @override
  String get noCategoriesAvailable =>
      'Aucune catégorie disponible. Veuillez ajouter des catégories dans l\'écran Répartitions et Catégories.';

  @override
  String errorSavingBill(String error) {
    return 'Erreur lors de l\'enregistrement de la facture : $error';
  }

  @override
  String get to => 'à';

  @override
  String get addCategoriesToOrganize =>
      'Ajoutez des catégories pour organiser vos factures';

  @override
  String get inUseCannotDelete =>
      'En cours d\'utilisation (ne peut pas être supprimé)';

  @override
  String get googleDriveConnection => 'Connexion Google Drive';

  @override
  String get googleDriveFolder => 'Dossier Google Drive';

  @override
  String get selectGoogleDriveFolderPrompt =>
      'Veuillez sélectionner un dossier Google Drive où vos données seront stockées :';

  @override
  String get selectGoogleDriveFolderMessage =>
      'Veuillez sélectionner un dossier Google Drive où vos données seront stockées. Vous devez sélectionner un dossier avant d\'accéder aux autres fonctionnalités.';

  @override
  String get personNames => 'Noms des personnes';

  @override
  String get selectOrNavigateFolder =>
      'Sélectionnez ou naviguez dans un dossier :';

  @override
  String get saveConfiguration => 'Enregistrer la configuration';

  @override
  String get goBack => 'Retour';

  @override
  String get navigateIntoFolder => 'Naviguer dans le dossier';

  @override
  String get selectThisFolder => 'Sélectionner ce dossier';

  @override
  String get allBalancedNoOneOwes =>
      'Tout équilibré ! Personne ne doit rien à personne.';

  @override
  String personOwesPerson(String person1, String person2, String amount) {
    return '$person1 doit $amount à $person2';
  }

  @override
  String get currentlyUsedFolder => 'Dossier actuellement utilisé :';

  @override
  String get folderName => 'Nom du dossier';

  @override
  String get enterFolderName => 'Entrez le nom du dossier';
}
